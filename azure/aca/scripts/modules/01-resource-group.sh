#!/bin/bash

# =============================================================================
# Resource Group Deployment Module
# =============================================================================
# Creates the Azure Resource Group for all xshopai resources.
#
# Required Environment Variables:
#   - RESOURCE_GROUP: Name of the resource group
#   - LOCATION: Azure region
#   - PROJECT_NAME: Project name for tagging
#   - ENVIRONMENT: Environment name (dev/prod)
#   - SUFFIX: Unique suffix for resources
#
# Exports:
#   - (none - resource group is a container for other resources)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_resource_group() {
    print_header "Creating Resource Group"
    
    # Validate required variables
    validate_required_vars "RESOURCE_GROUP" "LOCATION" "PROJECT_NAME" "ENVIRONMENT" "SUFFIX" || return 1
    
    # Check if already exists
    if resource_exists "group" "$RESOURCE_GROUP"; then
        print_warning "Resource Group already exists: $RESOURCE_GROUP"
        return 0
    fi
    
    # Create resource group
    if az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags "project=$PROJECT_NAME" "environment=$ENVIRONMENT" "suffix=$SUFFIX" \
        --output none 2>&1; then
        print_success "Resource Group created: $RESOURCE_GROUP"
        return 0
    else
        print_error "Failed to create Resource Group: $RESOURCE_GROUP"
        return 1
    fi
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_resource_group
fi
