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
#   - SUBSCRIPTION_ID: Azure subscription ID
#   - IDENTITY_PRINCIPAL_ID: Managed identity principal ID (for role assignments)
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
    
    # Retrieve connection string (for backward compatibility, though MI is preferred)
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
    
    # Grant managed identity Service Bus Data Owner role (allows send AND receive)
    if [ -n "$IDENTITY_PRINCIPAL_ID" ]; then
        print_info "Granting managed identity Service Bus access..."
        print_info "  Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID"
        local SB_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ServiceBus/namespaces/$SERVICE_BUS"
        print_info "  Service Bus Scope: $SB_SCOPE"
        
        if create_role_assignment "$IDENTITY_PRINCIPAL_ID" "Azure Service Bus Data Owner" "$SB_SCOPE" "ServicePrincipal"; then
            print_success "Service Bus Data Owner role assignment created for managed identity"
        else
            print_warning "Service Bus role assignment may already exist or failed"
        fi
    else
        print_warning "IDENTITY_PRINCIPAL_ID is empty - skipping Service Bus role assignment!"
        print_warning "This will cause Dapr pubsub to fail if managed identity auth is used!"
    fi
    
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
