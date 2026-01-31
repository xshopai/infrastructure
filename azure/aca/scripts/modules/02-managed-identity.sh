#!/bin/bash

# =============================================================================
# Managed Identity Deployment Module
# =============================================================================
# Creates a User-Assigned Managed Identity for service authentication.
#
# Required Environment Variables:
#   - MANAGED_IDENTITY: Name of the managed identity
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Exports:
#   - IDENTITY_ID: Full resource ID of the identity
#   - IDENTITY_CLIENT_ID: Client ID for authentication
#   - IDENTITY_PRINCIPAL_ID: Principal ID for role assignments
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_managed_identity() {
    print_header "Creating Managed Identity"
    
    # Validate required variables
    validate_required_vars "MANAGED_IDENTITY" "RESOURCE_GROUP" "LOCATION" || return 1
    
    # Check if already exists
    if resource_exists "identity" "$MANAGED_IDENTITY" "$RESOURCE_GROUP"; then
        print_warning "Managed Identity already exists: $MANAGED_IDENTITY"
    else
        # Create managed identity
        if az identity create \
            --name "$MANAGED_IDENTITY" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none 2>&1; then
            print_success "Managed Identity created: $MANAGED_IDENTITY"
        else
            print_error "Failed to create Managed Identity: $MANAGED_IDENTITY"
            return 1
        fi
    fi
    
    # Retrieve identity properties
    export IDENTITY_ID=$(az identity show \
        --name "$MANAGED_IDENTITY" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)
    
    export IDENTITY_CLIENT_ID=$(az identity show \
        --name "$MANAGED_IDENTITY" \
        --resource-group "$RESOURCE_GROUP" \
        --query clientId -o tsv)
    
    export IDENTITY_PRINCIPAL_ID=$(az identity show \
        --name "$MANAGED_IDENTITY" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    
    if [ -z "$IDENTITY_ID" ] || [ -z "$IDENTITY_CLIENT_ID" ] || [ -z "$IDENTITY_PRINCIPAL_ID" ]; then
        print_error "Failed to retrieve Managed Identity properties"
        return 1
    fi
    
    print_info "Identity ID: $IDENTITY_ID"
    print_info "Client ID: $IDENTITY_CLIENT_ID"
    print_info "Principal ID: $IDENTITY_PRINCIPAL_ID"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_managed_identity
fi
