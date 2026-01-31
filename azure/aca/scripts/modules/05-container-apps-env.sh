#!/bin/bash

# =============================================================================
# Container Apps Environment Deployment Module
# =============================================================================
# Creates the Azure Container Apps Environment for hosting microservices.
#
# Required Environment Variables:
#   - CONTAINER_ENV: Name of the Container Apps Environment
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#   - LOG_ANALYTICS_ID: Log Analytics workspace ID
#   - LOG_ANALYTICS_KEY: Log Analytics workspace key
#
# Exports:
#   - (none)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_container_apps_env() {
    print_header "Creating Container Apps Environment"
    
    # Validate required variables
    validate_required_vars "CONTAINER_ENV" "RESOURCE_GROUP" "LOCATION" "LOG_ANALYTICS_ID" "LOG_ANALYTICS_KEY" || return 1
    
    print_warning "This may take 2-5 minutes..."
    
    # Check if already exists
    if resource_exists "containerapp-env" "$CONTAINER_ENV" "$RESOURCE_GROUP"; then
        print_warning "Container Apps Environment already exists: $CONTAINER_ENV"
        return 0
    fi
    
    # Create Container Apps Environment (matching deploy-infra.sh)
    if az containerapp env create \
        --name "$CONTAINER_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$LOG_ANALYTICS_ID" \
        --logs-workspace-key "$LOG_ANALYTICS_KEY" \
        --output none 2>&1; then
        print_success "Container Apps Environment created: $CONTAINER_ENV"
        return 0
    else
        print_error "Failed to create Container Apps Environment: $CONTAINER_ENV"
        return 1
    fi
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_container_apps_env
fi
