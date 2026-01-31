#!/bin/bash

# =============================================================================
# Azure Service Bus Deployment Module
# =============================================================================
# Creates an Azure Service Bus namespace for messaging between services.
#
# Required Environment Variables:
#   - SERVICE_BUS: Name of the Service Bus namespace
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Exports:
#   - SERVICE_BUS_CONNECTION: Connection string for Service Bus
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_service_bus() {
    print_header "Creating Azure Service Bus"
    
    # Validate required variables
    validate_required_vars "SERVICE_BUS" "RESOURCE_GROUP" "LOCATION" || return 1
    
    # Check if already exists
    if resource_exists "servicebus" "$SERVICE_BUS" "$RESOURCE_GROUP"; then
        print_warning "Service Bus already exists: $SERVICE_BUS"
    else
        # Create Service Bus namespace with Standard SKU (matching deploy-infra.sh)
        if az servicebus namespace create \
            --name "$SERVICE_BUS" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --output none 2>&1; then
            print_success "Service Bus Namespace created: $SERVICE_BUS"
        else
            print_error "Failed to create Service Bus Namespace: $SERVICE_BUS"
            return 1
        fi
    fi
    
    # Retrieve connection string
    export SERVICE_BUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
        --namespace-name "$SERVICE_BUS" \
        --resource-group "$RESOURCE_GROUP" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString -o tsv)
    
    if [ -z "$SERVICE_BUS_CONNECTION" ]; then
        print_error "Failed to retrieve Service Bus connection string"
        return 1
    fi
    
    print_info "Service Bus connection string retrieved"
    
    # Configure network rules
    print_info "Configuring Service Bus network rules..."
    if az servicebus namespace network-rule-set update \
        --namespace-name "$SERVICE_BUS" \
        --resource-group "$RESOURCE_GROUP" \
        --default-action Allow \
        --enable-trusted-service-access true \
        --output none 2>/dev/null; then
        print_success "Service Bus network rules configured"
    else
        print_warning "Service Bus network rules configuration skipped (may not be supported on Standard tier)"
    fi
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_service_bus
fi
