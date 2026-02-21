#!/bin/bash

# =============================================================================
# Azure Container Registry (ACR) Deployment Module
# =============================================================================
# Creates an Azure Container Registry for storing container images.
#
# Required Environment Variables:
#   - ACR_NAME: Name of the container registry (no hyphens)
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#   - IDENTITY_PRINCIPAL_ID: Principal ID for AcrPull role assignment
#   - SUBSCRIPTION_ID: Azure subscription ID
#
# Exports:
#   - ACR_LOGIN_SERVER: Login server URL (e.g., myacr.azurecr.io)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_acr() {
    print_header "Creating Azure Container Registry"
    
    # Validate required variables
    validate_required_vars "ACR_NAME" "RESOURCE_GROUP" "LOCATION" || return 1
    
    # Check if already exists
    if resource_exists "acr" "$ACR_NAME" "$RESOURCE_GROUP"; then
        print_warning "Container Registry already exists: $ACR_NAME"
    else
        # Create ACR with Basic SKU (matching deploy-infra.sh)
        # admin-enabled true is required for service deployments
        if az acr create \
            --name "$ACR_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Basic \
            --admin-enabled true \
            --output none 2>&1; then
            print_success "Container Registry created: $ACR_NAME"
        else
            print_error "Failed to create Container Registry: $ACR_NAME"
            return 1
        fi
    fi
    
    # Get login server
    export ACR_LOGIN_SERVER=$(az acr show \
        --name "$ACR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query loginServer -o tsv)
    
    if [ -z "$ACR_LOGIN_SERVER" ]; then
        print_error "Failed to retrieve ACR login server"
        return 1
    fi
    
    print_info "ACR Login Server: $ACR_LOGIN_SERVER"
    
    # Grant managed identity AcrPull role
    if [ -n "$IDENTITY_PRINCIPAL_ID" ] && [ -n "$SUBSCRIPTION_ID" ]; then
        print_info "Granting managed identity AcrPull access..."
        local ACR_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"
        
        if create_role_assignment "$IDENTITY_PRINCIPAL_ID" "AcrPull" "$ACR_SCOPE" "ServicePrincipal"; then
            print_success "ACR role assignment created"
        else
            print_warning "ACR role assignment may already exist (continuing)"
        fi
    fi
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_acr
fi
