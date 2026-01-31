#!/bin/bash

# =============================================================================
# Azure Cache for Redis Deployment Module
# =============================================================================
# Creates an Azure Cache for Redis for caching and session storage.
#
# Required Environment Variables:
#   - REDIS_NAME: Name of the Redis cache
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Exports:
#   - REDIS_HOST: Redis hostname
#   - REDIS_KEY: Primary access key
#   - REDIS_CONNECTION: Full connection string
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_redis() {
    print_header "Creating Azure Cache for Redis"
    
    # Validate required variables
    validate_required_vars "REDIS_NAME" "RESOURCE_GROUP" "LOCATION" || return 1
    
    print_warning "This may take 5-10 minutes..."
    
    # Check if already exists
    if resource_exists "redis" "$REDIS_NAME" "$RESOURCE_GROUP"; then
        print_warning "Redis Cache already exists: $REDIS_NAME"
    else
        # Create Redis cache with Basic SKU (matching deploy-infra.sh)
        if az redis create \
            --name "$REDIS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Basic \
            --vm-size c0 \
            --output none 2>&1; then
            print_success "Redis Cache created: $REDIS_NAME"
        else
            print_error "Failed to create Redis Cache: $REDIS_NAME"
            return 1
        fi
    fi
    
    # Retrieve Redis properties
    export REDIS_HOST=$(az redis show \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query hostName -o tsv)
    
    export REDIS_KEY=$(az redis list-keys \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryKey -o tsv)
    
    if [ -z "$REDIS_HOST" ] || [ -z "$REDIS_KEY" ]; then
        print_error "Failed to retrieve Redis properties"
        return 1
    fi
    
    export REDIS_CONNECTION="${REDIS_HOST}:6380,password=${REDIS_KEY},ssl=True,abortConnect=False"
    
    print_info "Redis Host: $REDIS_HOST"
    print_success "Redis Cache configured"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_redis
fi
