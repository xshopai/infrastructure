#!/bin/bash

# =============================================================================
# Azure Key Vault Deployment Module
# =============================================================================
# Creates an Azure Key Vault for secrets management and stores platform secrets.
#
# Required Environment Variables:
#   - KEY_VAULT: Name of the Key Vault
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#   - SUBSCRIPTION_ID: Azure subscription ID
#   - IDENTITY_PRINCIPAL_ID: Managed identity principal ID (for secrets access)
#
# Secret Dependencies (optional - will skip if not set):
#   - SERVICE_BUS_CONNECTION
#   - REDIS_KEY
#   - COSMOS_CONNECTION
#   - MYSQL_SERVER_CONNECTION
#   - SQL_SERVER_CONNECTION
#   - POSTGRES_SERVER_CONNECTION
#   - APP_INSIGHTS_CONNECTION_STRING
#
# Exports:
#   - KEY_VAULT_URL: Key Vault URL (https://<name>.vault.azure.net/)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_keyvault() {
    print_header "Creating Azure Key Vault"
    
    # Validate required variables
    validate_required_vars "KEY_VAULT" "RESOURCE_GROUP" "LOCATION" "SUBSCRIPTION_ID" || return 1
    
    # Check if already exists
    if resource_exists "keyvault" "$KEY_VAULT" "$RESOURCE_GROUP"; then
        print_warning "Key Vault already exists: $KEY_VAULT (will update configuration)"
    else
        # Create Key Vault (matching deploy-infra.sh)
        if az keyvault create \
            --name "$KEY_VAULT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --enable-rbac-authorization true \
            --public-network-access Enabled \
            --output none 2>&1; then
            print_success "Key Vault created: $KEY_VAULT"
        else
            print_error "Failed to create Key Vault: $KEY_VAULT"
            return 1
        fi
    fi
    
    # Configure network rules - IMPORTANT: Allow public access for Dapr secretstore
    # Without this, Dapr containers in ACA cannot access Key Vault secrets
    print_info "Configuring Key Vault network access (public access enabled for Dapr)..."
    
    # Use REST API to ensure public network access is enabled (more reliable than CLI)
    local KV_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT}"
    
    # First check current state
    local CURRENT_STATE=$(az rest --method get \
        --url "https://management.azure.com${KV_ID}?api-version=2023-07-01" \
        --query "properties.publicNetworkAccess" -o tsv 2>/dev/null || echo "Unknown")
    print_info "Current Key Vault public network access: $CURRENT_STATE"
    
    # Enable public access using REST API (bypasses any CLI quirks)
    if az rest --method patch \
        --url "https://management.azure.com${KV_ID}?api-version=2023-07-01" \
        --body '{"properties":{"publicNetworkAccess":"Enabled","networkAcls":{"bypass":"AzureServices","defaultAction":"Allow"}}}' \
        --output none 2>/dev/null; then
        print_success "Key Vault network rules configured via REST API"
    else
        # Fallback to CLI
        print_warning "REST API failed, trying CLI..."
        if az keyvault update \
            --name "$KEY_VAULT" \
            --resource-group "$RESOURCE_GROUP" \
            --public-network-access Enabled \
            --default-action Allow \
            --bypass AzureServices \
            --output none; then
            print_success "Key Vault network rules configured via CLI"
        else
            print_error "Failed to configure Key Vault network rules"
            return 1
        fi
    fi
    
    # Verify the setting was applied
    local FINAL_STATE=$(az rest --method get \
        --url "https://management.azure.com${KV_ID}?api-version=2023-07-01" \
        --query "properties.publicNetworkAccess" -o tsv 2>/dev/null || echo "Unknown")
    if [ "$FINAL_STATE" = "Enabled" ]; then
        print_success "Verified: Key Vault public network access is Enabled"
    else
        print_error "Warning: Key Vault public network access is '$FINAL_STATE' (expected 'Enabled')"
        print_error "Dapr secretstore may fail to access secrets!"
    fi
    
    # Grant managed identity Key Vault Secrets User role
    if [ -n "$IDENTITY_PRINCIPAL_ID" ]; then
        print_info "Granting managed identity Key Vault access..."
        print_info "  Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID"
        local KV_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT"
        print_info "  Key Vault Scope: $KV_SCOPE"
        
        if create_role_assignment "$IDENTITY_PRINCIPAL_ID" "Key Vault Secrets User" "$KV_SCOPE" "ServicePrincipal"; then
            print_success "Key Vault role assignment created for managed identity"
        else
            print_error "Failed to create Key Vault role assignment for managed identity"
        fi
    else
        print_warning "IDENTITY_PRINCIPAL_ID is empty - skipping Key Vault role assignment!"
        print_warning "This will cause Dapr secretstore to fail at runtime!"
    fi
    
    # Grant current user Key Vault Secrets Officer role
    local CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    if [ -n "$CURRENT_USER_ID" ]; then
        print_info "Granting current user Key Vault Secrets Officer role..."
        local KV_USER_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT"
        
        if create_role_assignment "$CURRENT_USER_ID" "Key Vault Secrets Officer" "$KV_USER_SCOPE" "User"; then
            print_success "Key Vault role assignment created for current user"
        else
            print_warning "Role assignment may already exist"
        fi
        
        # Wait for role assignment to propagate
        print_info "Waiting for role assignment to propagate (15s)..."
        sleep 15
    fi
    
    export KEY_VAULT_URL="https://${KEY_VAULT}.vault.azure.net/"
    print_info "Key Vault URL: $KEY_VAULT_URL"
    
    return 0
}

store_keyvault_secrets() {
    print_header "Storing Secrets in Key Vault"
    
    validate_required_vars "KEY_VAULT" || return 1
    
    local SECRET_COUNT=0
    
    # Helper function to store a secret
    store_secret() {
        local name="$1"
        local value="$2"
        
        if [ -n "$value" ]; then
            if az keyvault secret set --vault-name "$KEY_VAULT" --name "$name" --value "$value" --output none 2>/dev/null; then
                print_success "Stored: $name"
                SECRET_COUNT=$((SECRET_COUNT + 1))
            else
                print_warning "Failed to store: $name"
            fi
        else
            print_warning "Skipped: $name (no value)"
        fi
    }
    
    print_info "Storing platform infrastructure secrets..."
    
    # Platform infrastructure secrets (xshopai- prefix)
    store_secret "xshopai-servicebus-connection" "$SERVICE_BUS_CONNECTION"
    store_secret "xshopai-redis-password" "$REDIS_KEY"
    store_secret "xshopai-cosmos-account-connection" "$COSMOS_CONNECTION"
    store_secret "xshopai-mysql-server-connection" "$MYSQL_SERVER_CONNECTION"
    store_secret "xshopai-sql-server-connection" "$SQL_SERVER_CONNECTION"
    store_secret "xshopai-postgres-server-connection" "$POSTGRES_SERVER_CONNECTION"
    store_secret "xshopai-appinsights-connection" "$APP_INSIGHTS_CONNECTION_STRING"
    
    # Application secrets (generate if not exists)
    print_info "Storing application secrets..."
    
    # JWT Secret
    local JWT_SECRET_VALUE=$(openssl rand -base64 32)
    store_secret "xshopai-jwt-secret" "$JWT_SECRET_VALUE"
    
    # Flask Secret
    local FLASK_SECRET_VALUE=$(openssl rand -hex 24)
    store_secret "xshopai-flask-secret" "$FLASK_SECRET_VALUE"
    
    # Service-to-service tokens
    print_info "Storing service-to-service tokens..."
    store_secret "xshopai-svc-product-token" "$(openssl rand -hex 16)"
    store_secret "xshopai-svc-order-token" "$(openssl rand -hex 16)"
    store_secret "xshopai-svc-cart-token" "$(openssl rand -hex 16)"
    store_secret "xshopai-svc-webbff-token" "$(openssl rand -hex 16)"
    
    print_success "Stored $SECRET_COUNT secrets in Key Vault"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_keyvault
    store_keyvault_secrets
fi
