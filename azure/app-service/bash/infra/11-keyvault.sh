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
#   - Redis, RabbitMQ, ACR credentials (from infra deployment)
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
    # Step 2: Store All Secrets
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
    # SHARED CREDENTIALS (used for re-runs)
    # =========================================================================
    print_info "Storing shared credentials..."
    store_secret "db-admin-password" "$DB_ADMIN_PASSWORD"
    
    # =========================================================================
    # ACR CREDENTIALS
    # =========================================================================
    print_info "Storing ACR credentials..."
    store_secret "acr-server" "$ACR_LOGIN_SERVER"
    store_secret "acr-username" "$ACR_USERNAME"
    store_secret "acr-password" "$ACR_PASSWORD"
    
    # =========================================================================
    # MONGODB (Cosmos DB) - For user-service, product-service, review-service, auth-service
    # Format: Full MongoDB connection URI
    # =========================================================================
    print_info "Storing MongoDB connection strings..."
    
    # Shared MongoDB settings
    store_secret "mongodb-connection" "$COSMOS_CONNECTION"
    store_secret "mongodb-endpoint" "$COSMOS_ENDPOINT"
    
    # Service-specific MongoDB URIs (with database name)
    # Services expect: MONGODB_URI=mongodb://...
    store_secret "user-service-mongodb-uri" "${COSMOS_CONNECTION}&database=user_service_db"
    store_secret "product-service-mongodb-uri" "${COSMOS_CONNECTION}&database=product_service_db"
    store_secret "review-service-mongodb-uri" "${COSMOS_CONNECTION}&database=review_service_db"
    store_secret "auth-service-mongodb-uri" "${COSMOS_CONNECTION}&database=auth_service_db"
    
    # =========================================================================
    # POSTGRESQL - For audit-service, order-processor-service
    # Format: Individual vars (audit uses them separately)
    # =========================================================================
    print_info "Storing PostgreSQL connection info..."
    
    store_secret "postgres-host" "$POSTGRES_HOST"
    store_secret "postgres-port" "5432"
    store_secret "postgres-user" "$POSTGRES_ADMIN_USER"
    store_secret "postgres-password" "$POSTGRES_ADMIN_PASSWORD"
    
    # Full connection string for services that prefer it
    local pg_audit_conn="postgresql://${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/audit_service_db?sslmode=require"
    local pg_orderproc_conn="postgresql://${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/order_processor_db?sslmode=require"
    store_secret "audit-service-postgres-url" "$pg_audit_conn"
    store_secret "order-processor-postgres-url" "$pg_orderproc_conn"
    
    # =========================================================================
    # MYSQL - For inventory-service
    # Format: mysql+pymysql://user:pass@host:port (Python SQLAlchemy format)
    # =========================================================================
    print_info "Storing MySQL connection string..."
    
    store_secret "mysql-host" "$MYSQL_HOST"
    store_secret "mysql-user" "$MYSQL_ADMIN_USER"
    store_secret "mysql-password" "$MYSQL_ADMIN_PASSWORD"
    
    # inventory-service expects: MYSQL_SERVER_CONNECTION
    local mysql_inventory_conn="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306"
    store_secret "inventory-service-mysql-connection" "$mysql_inventory_conn"
    
    # =========================================================================
    # SQL SERVER - For order-service, payment-service
    # Format: .NET SQL Server connection string
    # =========================================================================
    print_info "Storing SQL Server connection strings..."
    
    store_secret "sql-host" "$SQL_HOST"
    store_secret "sql-user" "$SQL_ADMIN_USER"
    store_secret "sql-password" "$SQL_ADMIN_PASSWORD"
    
    # order-service expects: DATABASE_CONNECTION_STRING
    local sql_order_conn="Server=${SQL_HOST};Database=order_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    store_secret "order-service-sql-connection" "$sql_order_conn"
    
    # payment-service expects: ConnectionStrings__DefaultConnection
    local sql_payment_conn="Server=${SQL_HOST};Database=payment_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    store_secret "payment-service-sql-connection" "$sql_payment_conn"
    
    # =========================================================================
    # REDIS - For cart-service
    # Format: redis://:password@host:port (Quarkus Redis client format)
    # =========================================================================
    print_info "Storing Redis connection info..."
    
    store_secret "redis-host" "$REDIS_HOST"
    store_secret "redis-port" "6380"
    store_secret "redis-password" "$REDIS_KEY"
    
    # cart-service expects: quarkus.redis.hosts format (SSL on port 6380)
    local redis_cart_url="rediss://:${REDIS_KEY}@${REDIS_HOST}:6380"
    store_secret "cart-service-redis-url" "$redis_cart_url"
    
    # =========================================================================
    # RABBITMQ - For all services
    # Format: amqp://user:pass@host:port (AMQP URL format)
    # =========================================================================
    print_info "Storing RabbitMQ connection info..."
    
    store_secret "rabbitmq-host" "$RABBITMQ_HOST"
    store_secret "rabbitmq-port" "5672"
    store_secret "rabbitmq-user" "$RABBITMQ_USER"
    store_secret "rabbitmq-password" "$RABBITMQ_PASSWORD"
    
    # Full connection URL (used by most Node.js and Python services)
    local rabbitmq_url="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:5672/"
    store_secret "rabbitmq-url" "$rabbitmq_url"
    store_secret "rabbitmq-management-url" "http://${RABBITMQ_HOST}:15672"
    
    # =========================================================================
    # APPLICATION INSIGHTS - For all services
    # =========================================================================
    print_info "Storing Application Insights credentials..."
    
    store_secret "appinsights-connection-string" "$APP_INSIGHTS_CONNECTION"
    store_secret "appinsights-instrumentation-key" "$APP_INSIGHTS_KEY"
    
    # =========================================================================
    # JWT SECRET - Shared across all services for token validation
    # =========================================================================
    print_info "Storing JWT secret..."
    
    # Check if JWT secret already exists (for consistency across re-runs)
    local existing_jwt=$(az keyvault secret show --vault-name "$KEY_VAULT" --name "jwt-secret" --query value -o tsv 2>/dev/null || echo "")
    if [ -n "$existing_jwt" ]; then
        export JWT_SECRET="$existing_jwt"
        print_info "  Using existing JWT secret"
    else
        export JWT_SECRET=$(openssl rand -base64 32)
        store_secret "jwt-secret" "$JWT_SECRET"
    fi
    
    # JWT configuration
    store_secret "jwt-issuer" "auth-service"
    store_secret "jwt-audience" "xshopai-platform"
    store_secret "jwt-algorithm" "HS256"
    store_secret "jwt-expires-in" "24h"
    store_secret "jwt-refresh-expires-in" "7d"
    
    # =========================================================================
    # SERVICE-TO-SERVICE AUTHENTICATION TOKENS
    # Each service gets a unique token for identifying itself to other services
    # =========================================================================
    print_info "Storing service-to-service tokens..."
    
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
    
    # Service tokens (each service uses these to authenticate to other services)
    local token_admin=$(generate_or_get_token "admin-service-token")
    local token_auth=$(generate_or_get_token "auth-service-token")
    local token_user=$(generate_or_get_token "user-service-token")
    local token_product=$(generate_or_get_token "product-service-token")
    local token_inventory=$(generate_or_get_token "inventory-service-token")
    local token_cart=$(generate_or_get_token "cart-service-token")
    local token_order=$(generate_or_get_token "order-service-token")
    local token_orderproc=$(generate_or_get_token "order-processor-service-token")
    local token_payment=$(generate_or_get_token "payment-service-token")
    local token_review=$(generate_or_get_token "review-service-token")
    local token_notification=$(generate_or_get_token "notification-service-token")
    local token_audit=$(generate_or_get_token "audit-service-token")
    local token_chat=$(generate_or_get_token "chat-service-token")
    local token_webbff=$(generate_or_get_token "web-bff-token")
    
    store_secret "admin-service-token" "$token_admin"
    store_secret "auth-service-token" "$token_auth"
    store_secret "user-service-token" "$token_user"
    store_secret "product-service-token" "$token_product"
    store_secret "inventory-service-token" "$token_inventory"
    store_secret "cart-service-token" "$token_cart"
    store_secret "order-service-token" "$token_order"
    store_secret "order-processor-service-token" "$token_orderproc"
    store_secret "payment-service-token" "$token_payment"
    store_secret "review-service-token" "$token_review"
    store_secret "notification-service-token" "$token_notification"
    store_secret "audit-service-token" "$token_audit"
    store_secret "chat-service-token" "$token_chat"
    store_secret "web-bff-token" "$token_webbff"
    
    # =========================================================================
    # AZURE OPENAI (for chat-service) - Placeholder
    # =========================================================================
    print_info "Storing Azure OpenAI placeholders..."
    
    # These should be set after deployment via Azure Portal or CLI
    store_secret "azure-openai-endpoint" "${AZURE_OPENAI_ENDPOINT:-placeholder-set-after-deployment}"
    store_secret "azure-openai-api-key" "${AZURE_OPENAI_API_KEY:-placeholder-set-after-deployment}"
    store_secret "azure-openai-deployment-name" "${AZURE_OPENAI_DEPLOYMENT_NAME:-gpt-4o}"
    
    print_success "All secrets stored in Key Vault"
    print_info "Key Vault URL: $KEY_VAULT_URL"
    
    # =========================================================================
    # Print Summary
    # =========================================================================
    echo ""
    print_header "Secrets Summary"
    echo "MongoDB services:"
    echo "  - user-service-mongodb-uri"
    echo "  - product-service-mongodb-uri"
    echo "  - review-service-mongodb-uri"
    echo "  - auth-service-mongodb-uri"
    echo ""
    echo "PostgreSQL services:"
    echo "  - audit-service-postgres-url"
    echo "  - order-processor-postgres-url"
    echo ""
    echo "MySQL services:"
    echo "  - inventory-service-mysql-connection"
    echo ""
    echo "SQL Server services:"
    echo "  - order-service-sql-connection"
    echo "  - payment-service-sql-connection"
    echo ""
    echo "Redis services:"
    echo "  - cart-service-redis-url"
    echo ""
    echo "Shared:"
    echo "  - rabbitmq-url, jwt-secret, appinsights-connection-string"
    echo "  - 14 service-to-service tokens (*-service-token)"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_keyvault
fi
