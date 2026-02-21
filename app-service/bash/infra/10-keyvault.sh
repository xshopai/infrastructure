#!/bin/bash

# =============================================================================
# Azure Key Vault Deployment Module (with Secrets Storage)
# =============================================================================
# Creates Key Vault and stores all infrastructure secrets in the exact format
# that each service expects during deployment.
#
# Secrets are stored as complete connection strings ready for injection.
# Service-to-service tokens are auto-generated for secure communication.
#
# Required Environment Variables:
#   - KEY_VAULT, RESOURCE_GROUP, LOCATION, SUBSCRIPTION_ID
#   - Database hosts and credentials (from infra deployment)
#   - Redis, RabbitMQ credentials (from infra deployment)
#
# Exports:
#   - KEY_VAULT_URL: Key Vault URL
#   - JWT_SECRET: Generated JWT secret
# =============================================================================

set -e

deploy_keyvault() {
    print_header "Creating Key Vault & Storing Secrets"
    
    # Validate required variables
    validate_required_vars "KEY_VAULT" "RESOURCE_GROUP" "LOCATION" "SUBSCRIPTION_ID" || return 1
    
    # -------------------------------------------------------------------------
    # Step 1: Create Key Vault (using access policies, not RBAC)
    # -------------------------------------------------------------------------
    if az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "Key Vault exists: $KEY_VAULT (skipping creation)"
    else
        print_info "Creating Key Vault..."
        if az keyvault create \
            --name "$KEY_VAULT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --enable-rbac-authorization false \
            --public-network-access Enabled \
            --output none 2>&1; then
            print_success "Key Vault created: $KEY_VAULT"
        else
            print_error "Failed to create Key Vault"
            return 1
        fi
    fi
    
    export KEY_VAULT_URL="https://${KEY_VAULT}.vault.azure.net/"
    
    # -------------------------------------------------------------------------
    # Step 1.5: Grant Access Policies to Current User
    # -------------------------------------------------------------------------
    print_info "Granting access policies to current user..."
    local current_user_oid=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
    
    if [ -n "$current_user_oid" ]; then
        az keyvault set-policy \
            --name "$KEY_VAULT" \
            --object-id "$current_user_oid" \
            --secret-permissions get list set delete purge \
            --output none 2>/dev/null
        print_success "Access policies granted to current user"
    else
        print_warning "Could not determine current user OID - trying with UPN"
        local current_user_upn=$(az account show --query user.name -o tsv 2>/dev/null)
        az keyvault set-policy \
            --name "$KEY_VAULT" \
            --upn "$current_user_upn" \
            --secret-permissions get list set delete purge \
            --output none 2>/dev/null
        print_success "Access policies granted via UPN"
    fi
    
    # Wait for access policies to propagate (avoid timing issues)
    print_info "Waiting for access policies to propagate (5 seconds)..."
    sleep 5
    
    # -------------------------------------------------------------------------
    # Step 2: Store All Secrets (Service-Specific + Shared Only)
    # -------------------------------------------------------------------------
    print_info "Storing secrets in Key Vault..."
    
    # Helper function
    store_secret() {
        local name="$1"
        local value="$2"
        if [ -n "$value" ]; then
            if az keyvault secret set --vault-name "$KEY_VAULT" --name "$name" --value "$value" --output none 2>/dev/null; then
                print_success "  $name"
            else
                print_warning "  Failed: $name"
            fi
        fi
    }
    
    # =========================================================================
    # SHARED SECRETS (Used by Multiple Services)
    # =========================================================================
    
    # -------------------------------------------------------------------------
    # JWT Configuration (auth-service issues, all services validate)
    # -------------------------------------------------------------------------
    print_info "Storing JWT shared secrets..."
    
    # Check if JWT secret already exists (for consistency across re-runs)
    local existing_jwt=$(az keyvault secret show --vault-name "$KEY_VAULT" --name "jwt-secret" --query value -o tsv 2>/dev/null || echo "")
    if [ -n "$existing_jwt" ]; then
        export JWT_SECRET="$existing_jwt"
        print_info "  Using existing JWT secret"
    else
        export JWT_SECRET=$(openssl rand -base64 32)
        store_secret "jwt-secret" "$JWT_SECRET"
    fi
    
    store_secret "jwt-issuer" "auth-service"
    store_secret "jwt-audience" "xshopai-platform"
    store_secret "jwt-algorithm" "HS256"
    store_secret "jwt-expires-in" "24h"
    
    # -------------------------------------------------------------------------
    # RabbitMQ (Event bus for all services)
    # -------------------------------------------------------------------------
    print_info "Storing RabbitMQ shared secret..."
    
    local rabbitmq_url="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:5672/"
    store_secret "rabbitmq-url" "$rabbitmq_url"
    
    # -------------------------------------------------------------------------
    # Application Insights (Telemetry for all services)
    # -------------------------------------------------------------------------
    print_info "Storing Application Insights shared secret..."
    
    store_secret "appinsights-connection-string" "$APP_INSIGHTS_CONNECTION"
    
    # =========================================================================
    # SERVICE-SPECIFIC DATABASE CONNECTIONS
    # =========================================================================
    
    # -------------------------------------------------------------------------
    # MongoDB (Cosmos DB) - user-service, product-service, review-service
    # -------------------------------------------------------------------------
    print_info "Storing service-specific MongoDB URIs..."
    
    # Use /dbname? format (database name in URI path) - required by MongoDB driver 5+
    # Pattern: replace /? with /dbname? in the base Cosmos connection string
    store_secret "user-service-mongodb-uri" "${COSMOS_CONNECTION/\/\?/\/user_service_db\?}"
    store_secret "product-service-mongodb-uri" "${COSMOS_CONNECTION/\/\?/\/product_service_db\?}"
    store_secret "review-service-mongodb-uri" "${COSMOS_CONNECTION/\/\?/\/review_service_db\?}"
    
    # -------------------------------------------------------------------------
    # PostgreSQL - audit-service, order-processor-service
    # -------------------------------------------------------------------------
    print_info "Storing service-specific PostgreSQL URLs..."
    
    local pg_audit_conn="postgresql://${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/audit_service_db?sslmode=require"
    local pg_orderproc_conn="jdbc:postgresql://${POSTGRES_HOST}:5432/order_processor_db?user=${POSTGRES_ADMIN_USER}&password=${POSTGRES_ADMIN_PASSWORD}&ssl=true"
    
    store_secret "audit-service-postgres-url" "$pg_audit_conn"
    store_secret "order-processor-service-postgres-url" "$pg_orderproc_conn"
    
    # -------------------------------------------------------------------------
    # MySQL - inventory-service
    # -------------------------------------------------------------------------
    print_info "Storing service-specific MySQL server connection..."
    
    local mysql_inventory_server="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306"
    store_secret "inventory-service-mysql-server" "$mysql_inventory_server"
    
    # -------------------------------------------------------------------------
    # SQL Server - order-service, payment-service
    # -------------------------------------------------------------------------
    print_info "Storing service-specific SQL Server connections..."
    
    local sql_order_conn="Server=${SQL_HOST};Database=order_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    local sql_payment_conn="Server=${SQL_HOST};Database=payment_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    
    store_secret "order-service-sql-connection" "$sql_order_conn"
    store_secret "payment-service-sql-connection" "$sql_payment_conn"
    
    # =========================================================================
    # SERVICE-TO-SERVICE AUTHENTICATION TOKENS
    # Each service gets a unique token for identifying itself to other services
    # =========================================================================
    print_info "Storing service-to-service authentication tokens..."
    
    # Generate or retrieve existing service tokens
    generate_or_get_token() {
        local token_name="$1"
        local existing=$(az keyvault secret show --vault-name "$KEY_VAULT" --name "$token_name" --query value -o tsv 2>/dev/null || echo "")
        if [ -n "$existing" ]; then
            echo "$existing"
        else
            # Generate: svc-{service}-{random}
            local random_part=$(openssl rand -hex 12)
            local service_name=$(echo "$token_name" | sed 's/-token$//')
            echo "svc-${service_name}-${random_part}"
        fi
    }
    
    # Only tokens that are loaded by service scripts via load_secret() are stored:
    #   admin-service-token    → admin-service.sh, user-service.sh
    #   auth-service-token     → user-service.sh
    #   user-service-token     → payment-service.sh
    #   cart-service-token     → cart-service.sh
    #   order-service-token    → payment-service.sh, user-service.sh, review-service.sh
    #   product-service-token  → review-service.sh
    #   web-bff-token          → user-service.sh, review-service.sh
    local token_admin=$(generate_or_get_token "admin-service-token")
    local token_auth=$(generate_or_get_token "auth-service-token")
    local token_user=$(generate_or_get_token "user-service-token")
    local token_cart=$(generate_or_get_token "cart-service-token")
    local token_order=$(generate_or_get_token "order-service-token")
    local token_product=$(generate_or_get_token "product-service-token")
    local token_webbff=$(generate_or_get_token "web-bff-token")
    
    store_secret "admin-service-token" "$token_admin"
    store_secret "auth-service-token" "$token_auth"
    store_secret "user-service-token" "$token_user"
    store_secret "cart-service-token" "$token_cart"
    store_secret "order-service-token" "$token_order"
    store_secret "product-service-token" "$token_product"
    store_secret "web-bff-token" "$token_webbff"

    # =========================================================================
    # DATABASE/MESSAGING CREDENTIALS (loaded directly by service scripts)
    # Postgres credentials: audit-service, order-processor-service
    # RabbitMQ credentials: cart-service, order-processor-service
    # =========================================================================
    print_info "Storing service credentials..."

    store_secret "postgres-admin-user" "$POSTGRES_ADMIN_USER"
    store_secret "postgres-admin-password" "$POSTGRES_ADMIN_PASSWORD"
    store_secret "rabbitmq-user" "$RABBITMQ_USER"
    store_secret "rabbitmq-password" "$RABBITMQ_PASSWORD"
    
    # =========================================================================
    # AZURE OPENAI (chat-service only)
    # =========================================================================
    print_info "Storing chat-service Azure OpenAI secrets..."
    
    # These should be set after deployment via Azure Portal or CLI
    store_secret "chat-service-openai-endpoint" "$AZURE_OPENAI_ENDPOINT"
    store_secret "chat-service-openai-api-key" "$AZURE_OPENAI_API_KEY"
    store_secret "chat-service-openai-deployment" "${AZURE_OPENAI_DEPLOYMENT_NAME:-gpt-4o}"
    
    print_success "All secrets stored in Key Vault (29 total)"
    print_info "Key Vault URL: $KEY_VAULT_URL"
    
    # =========================================================================
    # Print Summary
    # =========================================================================
    echo ""
    print_header "Secrets Summary"
    echo ""
    echo "SHARED SECRETS (7):"
    echo "  JWT: jwt-secret, jwt-issuer, jwt-audience, jwt-algorithm, jwt-expires-in"
    echo "  Event Bus: rabbitmq-url"
    echo "  Telemetry: appinsights-connection-string"
    echo ""
    echo "SERVICE-SPECIFIC DATABASE CONNECTIONS (8):"
    echo "  MongoDB: user-service-mongodb-uri, product-service-mongodb-uri, review-service-mongodb-uri"
    echo "  PostgreSQL: audit-service-postgres-url, order-processor-service-postgres-url"
    echo "  MySQL: inventory-service-mysql-server"
    echo "  SQL Server: order-service-sql-connection, payment-service-sql-connection"
    echo ""
    echo "SERVICE CREDENTIALS (4):"
    echo "  postgres-admin-user/password, rabbitmq-user/password"
    echo ""
    echo "SERVICE-TO-SERVICE TOKENS (7):"
    echo "  admin-service-token, auth-service-token, user-service-token"
    echo "  cart-service-token, order-service-token, product-service-token, web-bff-token"
    echo ""
    echo "AZURE OPENAI (3):"
    echo "  chat-service-openai-endpoint, chat-service-openai-api-key, chat-service-openai-deployment"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_keyvault
fi
