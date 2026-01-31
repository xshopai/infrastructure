#!/bin/bash

# =============================================================================
# Dapr Components Configuration Module
# =============================================================================
# Configures Dapr components in the Container Apps Environment.
#
# Required Environment Variables:
#   - CONTAINER_ENV: Container Apps Environment name
#   - RESOURCE_GROUP: Resource group name
#   - SERVICE_BUS_CONNECTION: Service Bus connection string
#   - REDIS_HOST: Redis host
#   - REDIS_KEY: Redis primary key
#   - KEY_VAULT: Key Vault name
#   - IDENTITY_CLIENT_ID: Managed identity client ID
#
# Exports:
#   - (none)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Define service scopes for Dapr components
DAPR_SERVICE_SCOPES="user-service,auth-service,product-service,order-service,cart-service,inventory-service,payment-service,notification-service,audit-service,review-service,order-processor-service,web-bff,admin-service,chat-service"

configure_dapr_components() {
    print_header "Configuring Dapr Components"
    
    # Validate required variables
    validate_required_vars "CONTAINER_ENV" "RESOURCE_GROUP" || return 1
    
    local COMPONENTS_CONFIGURED=0
    
    # -------------------------------------------------------------------------
    # Pub/Sub Component (Service Bus Topics)
    # -------------------------------------------------------------------------
    if [ -n "$SERVICE_BUS_CONNECTION" ]; then
        print_info "Configuring pubsub component (Service Bus Topics)..."
        
        cat > /tmp/dapr-pubsub.yaml << PUBSUBEOF
componentType: pubsub.azure.servicebus.topics
version: v1
metadata:
  - name: connectionString
    value: "${SERVICE_BUS_CONNECTION}"
  - name: maxActiveMessages
    value: "100"
  - name: maxConcurrentHandlers
    value: "10"
  - name: lockRenewalInSec
    value: "60"
scopes:
  - user-service
  - auth-service
  - product-service
  - order-service
  - cart-service
  - inventory-service
  - payment-service
  - notification-service
  - audit-service
  - review-service
  - order-processor-service
  - web-bff
  - admin-service
  - chat-service
PUBSUBEOF
        
        if az containerapp env dapr-component set \
            --name "$CONTAINER_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --dapr-component-name "pubsub" \
            --yaml /tmp/dapr-pubsub.yaml \
            --output none 2>&1; then
            print_success "Dapr pubsub component configured"
            COMPONENTS_CONFIGURED=$((COMPONENTS_CONFIGURED + 1))
        else
            print_error "Failed to configure Dapr pubsub component"
        fi
    else
        print_warning "Skipping pubsub component (no Service Bus connection)"
    fi
    
    # -------------------------------------------------------------------------
    # State Store Component (Redis)
    # -------------------------------------------------------------------------
    if [ -n "$REDIS_HOST" ] && [ -n "$REDIS_KEY" ]; then
        print_info "Configuring statestore component (Redis)..."
        
        local REDIS_PORT="${REDIS_PORT:-6380}"
        
        cat > /tmp/dapr-statestore.yaml << STATEEOF
componentType: state.redis
version: v1
metadata:
  - name: redisHost
    value: "${REDIS_HOST}:${REDIS_PORT}"
  - name: redisPassword
    value: "${REDIS_KEY}"
  - name: enableTLS
    value: "true"
  - name: actorStateStore
    value: "true"
scopes:
  - user-service
  - auth-service
  - product-service
  - order-service
  - cart-service
  - inventory-service
  - payment-service
  - notification-service
  - audit-service
  - review-service
  - order-processor-service
  - web-bff
  - admin-service
  - chat-service
STATEEOF
        
        if az containerapp env dapr-component set \
            --name "$CONTAINER_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --dapr-component-name "statestore" \
            --yaml /tmp/dapr-statestore.yaml \
            --output none 2>&1; then
            print_success "Dapr statestore component configured"
            COMPONENTS_CONFIGURED=$((COMPONENTS_CONFIGURED + 1))
        else
            print_error "Failed to configure Dapr statestore component"
        fi
    else
        print_warning "Skipping statestore component (missing Redis host or key)"
    fi
    
    # -------------------------------------------------------------------------
    # Secret Store Component (Key Vault)
    # -------------------------------------------------------------------------
    if [ -n "$KEY_VAULT" ] && [ -n "$IDENTITY_CLIENT_ID" ]; then
        print_info "Configuring secretstore component (Key Vault)..."
        
        cat > /tmp/dapr-secretstore.yaml << SECRETEOF
componentType: secretstores.azure.keyvault
version: v1
metadata:
  - name: vaultName
    value: "${KEY_VAULT}"
  - name: azureClientId
    value: "${IDENTITY_CLIENT_ID}"
scopes:
  - user-service
  - auth-service
  - product-service
  - order-service
  - cart-service
  - inventory-service
  - payment-service
  - notification-service
  - audit-service
  - review-service
  - order-processor-service
  - web-bff
  - admin-service
  - chat-service
SECRETEOF
        
        if az containerapp env dapr-component set \
            --name "$CONTAINER_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --dapr-component-name "secretstore" \
            --yaml /tmp/dapr-secretstore.yaml \
            --output none 2>&1; then
            print_success "Dapr secretstore component configured"
            COMPONENTS_CONFIGURED=$((COMPONENTS_CONFIGURED + 1))
        else
            print_error "Failed to configure Dapr secretstore component"
        fi
    else
        print_warning "Skipping secretstore component (missing Key Vault or Identity)"
    fi
    
    # Clean up temporary files
    rm -f /tmp/dapr-pubsub.yaml /tmp/dapr-statestore.yaml /tmp/dapr-secretstore.yaml
    
    print_success "Dapr components configured: $COMPONENTS_CONFIGURED/3"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_dapr_components
fi
