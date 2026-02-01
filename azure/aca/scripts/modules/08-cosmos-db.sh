#!/bin/bash

# =============================================================================
# Azure Cosmos DB Deployment Module
# =============================================================================
# Creates an Azure Cosmos DB account with MongoDB API for document storage.
#
# Required Environment Variables:
#   - COSMOS_ACCOUNT: Name of the Cosmos DB account
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Exports:
#   - COSMOS_CONNECTION: MongoDB connection string
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_cosmos_db() {
    print_header "Creating Azure Cosmos DB (MongoDB API)"
    
    # Validate required variables
    validate_required_vars "COSMOS_ACCOUNT" "RESOURCE_GROUP" "LOCATION" || return 1
    
    print_warning "This may take 5-10 minutes..."
    
    # Check if already exists
    if resource_exists "cosmos" "$COSMOS_ACCOUNT" "$RESOURCE_GROUP"; then
        print_warning "Cosmos DB account already exists: $COSMOS_ACCOUNT"
        
        # Ensure public network access is enabled (required for Container Apps connectivity)
        print_info "Verifying network access settings..."
        local CURRENT_ACCESS=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query publicNetworkAccess -o tsv 2>/dev/null || echo "Unknown")
        if [ "$CURRENT_ACCESS" != "Enabled" ]; then
            print_warning "Public network access is '$CURRENT_ACCESS', enabling it..."
            if az cosmosdb update \
                --name "$COSMOS_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --public-network-access Enabled \
                --output none 2>&1; then
                print_success "Public network access enabled for Cosmos DB"
            else
                print_error "Failed to enable public network access for Cosmos DB"
                return 1
            fi
        else
            print_success "Public network access is already enabled"
        fi
    else
        # Create Cosmos DB account with MongoDB API (matching deploy-infra.sh)
        # Note: isZoneRedundant=false to match original
        if az cosmosdb create \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=false \
            --kind MongoDB \
            --server-version "4.2" \
            --default-consistency-level Session \
            --enable-automatic-failover true \
            --disable-key-based-metadata-write-access false \
            --public-network-access Enabled \
            --output none 2>&1; then
            print_success "Cosmos DB account created: $COSMOS_ACCOUNT"
        else
            print_error "Failed to create Cosmos DB account: $COSMOS_ACCOUNT"
            return 1
        fi
    fi
    
    # Retrieve connection string
    export COSMOS_CONNECTION=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --type connection-strings \
        --query "connectionStrings[?keyKind=='Primary' && type=='MongoDB'].connectionString | [0]" -o tsv)
    
    if [ -z "$COSMOS_CONNECTION" ]; then
        print_error "Failed to retrieve Cosmos DB connection string"
        return 1
    fi
    
    print_info "Cosmos DB Host: ${COSMOS_ACCOUNT}.mongo.cosmos.azure.com"
    print_success "Cosmos DB configured"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_cosmos_db
fi
