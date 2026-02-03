#!/bin/bash

# =============================================================================
# Azure Communication Services Deployment Module
# =============================================================================
# Creates Azure Communication Services for email notifications.
#
# Required Environment Variables:
#   - COMMUNICATION_SERVICE: Name of the Communication Services resource
#   - EMAIL_DOMAIN_NAME: Domain name for email service (e.g., xshopai.com)
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region (use 'global' for ACS)
#   - DATA_LOCATION: Data residency location (e.g., UnitedStates, Europe)
#   - SUBSCRIPTION_ID: Azure subscription ID
#   - IDENTITY_PRINCIPAL_ID: Managed identity principal ID (for role assignments)
#
# Exports:
#   - ACS_CONNECTION_STRING: Connection string for Azure Communication Services
#   - ACS_ENDPOINT: Endpoint URL for ACS
#   - ACS_SENDER_ADDRESS: Email sender address (e.g., DoNotReply@<guid>.azurecomm.net)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_communication_service() {
    print_header "Creating Azure Communication Services"
    
    # Validate required variables
    validate_required_vars "COMMUNICATION_SERVICE" "RESOURCE_GROUP" "DATA_LOCATION" || return 1
    
    # Check if Communication Services resource exists
    if resource_exists "communication" "$COMMUNICATION_SERVICE" "$RESOURCE_GROUP"; then
        print_warning "Communication Services already exists: $COMMUNICATION_SERVICE"
    else
        # Create Azure Communication Services resource
        # Communication Services is a global resource
        # data-location determines where data is stored at rest (United States, Europe, etc.)
        print_info "Creating Communication Services resource..."
        if az communication create \
            --name "$COMMUNICATION_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --data-location "$DATA_LOCATION" \
            --location "global"; then
            print_success "Communication Services created: $COMMUNICATION_SERVICE"
        else
            print_error "Failed to create Communication Services: $COMMUNICATION_SERVICE"
            return 1
        fi
        
        # Wait for resource to be fully provisioned
        print_info "Waiting for Communication Services to be ready..."
        sleep 10
    fi
    
    # Retrieve connection string (using list-key command)
    print_info "Retrieving Communication Services connection string..."
    export ACS_CONNECTION_STRING=$(az communication list-key \
        --name "$COMMUNICATION_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "primaryConnectionString" -o tsv)
    
    if [ -z "$ACS_CONNECTION_STRING" ]; then
        print_error "Failed to retrieve Communication Services connection string"
        return 1
    fi
    print_success "Communication Services connection string retrieved"
    
    # Retrieve endpoint
    export ACS_ENDPOINT=$(az communication show \
        --name "$COMMUNICATION_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "hostName" -o tsv)
    
    if [ -z "$ACS_ENDPOINT" ]; then
        print_warning "Failed to retrieve Communication Services endpoint"
    else
        print_info "Communication Services endpoint: https://$ACS_ENDPOINT"
    fi
    
    # Create Email Communication Service (separate resource)
    local EMAIL_SERVICE_NAME="email-${COMMUNICATION_SERVICE}"
    
    if az communication email show \
        --name "$EMAIL_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "Email Communication Service already exists: $EMAIL_SERVICE_NAME"
    else
        print_info "Creating Email Communication Service..."
        if az communication email create \
            --name "$EMAIL_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --data-location "$DATA_LOCATION"; then
            print_success "Email Communication Service created: $EMAIL_SERVICE_NAME"
        else
            print_warning "Failed to create Email Communication Service (may not be available in this region)"
            print_info "Email functionality will work with connection string and managed domains"
        fi
    fi
    
    # Create Azure-managed domain for email sending
    print_info "Configuring Azure-managed email domain..."
    if az communication email domain show \
        --email-service-name "$EMAIL_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --domain-name "AzureManagedDomain" &>/dev/null; then
        print_success "Azure-managed email domain already exists"
    else
        print_info "Creating Azure-managed email domain..."
        if az communication email domain create \
            --name "AzureManagedDomain" \
            --email-service-name "$EMAIL_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --domain-management "AzureManaged" \
            --location "global"; then
            print_success "Azure-managed email domain created"
            
            # Wait for domain to be ready
            print_info "Waiting for email domain to be ready..."
            sleep 15
        else
            print_warning "Failed to create Azure-managed domain"
            print_info "You can create it manually via Azure Portal"
        fi
    fi
    
    # Export the sender address for use by notification-service
    # Azure-managed domains use format: DoNotReply@<guid>.azurecomm.net
    local DOMAIN_INFO=$(az communication email domain show \
        --email-service-name "$EMAIL_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --domain-name "AzureManagedDomain" \
        --query "mailFromSenderDomain" -o tsv 2>/dev/null)
    
    if [ -n "$DOMAIN_INFO" ]; then
        export ACS_SENDER_ADDRESS="DoNotReply@${DOMAIN_INFO}"
        print_success "Email sender address: $ACS_SENDER_ADDRESS"
    else
        print_warning "Could not determine sender address - check Azure Portal"
    fi
    
    # Link domain to Communication Services resource (required for sending emails)
    print_info "Linking email domain to Communication Services..."
    # Build the domain resource ID (MSYS_NO_PATHCONV prevents Git Bash path conversion)
    local DOMAIN_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Communication/emailServices/${EMAIL_SERVICE_NAME}/domains/AzureManagedDomain"
    
    # Check if already linked
    local CURRENT_LINKED=$(az communication show \
        --name "$COMMUNICATION_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "linkedDomains[0]" -o tsv 2>/dev/null)
    
    if [ -n "$CURRENT_LINKED" ]; then
        print_success "Email domain already linked to Communication Services"
    else
        # MSYS_NO_PATHCONV=1 prevents Git Bash from converting /subscriptions to C:/Program Files/Git/subscriptions
        if MSYS_NO_PATHCONV=1 az communication update \
            --name "$COMMUNICATION_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --linked-domains "$DOMAIN_RESOURCE_ID"; then
            print_success "Email domain linked to Communication Services"
        else
            print_warning "Failed to link domain - you may need to do this manually in Azure Portal"
        fi
    fi
    
    print_info "For production, configure a custom domain via Azure Portal:"
    print_info "  1. Go to Communication Services > Email > Domains"
    print_info "  2. Add custom domain (e.g., mail.xshopai.com)"
    print_info "  3. Verify domain ownership via DNS records"
    print_info "  4. Configure SPF, DKIM, and DMARC records"
    
    # Grant managed identity Communication Services access (if identity exists)
    if [ -n "$IDENTITY_PRINCIPAL_ID" ]; then
        print_info "Granting managed identity Communication Services access..."
        local ACS_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Communication/communicationServices/$COMMUNICATION_SERVICE"
        
        # Contributor role for sending emails
        if create_role_assignment "$IDENTITY_PRINCIPAL_ID" "Contributor" "$ACS_SCOPE" "ServicePrincipal"; then
            print_success "Communication Services Contributor role assigned to managed identity"
        else
            print_warning "Role assignment may already exist or failed (service will use connection string)"
        fi
    else
        print_warning "IDENTITY_PRINCIPAL_ID is empty - skipping role assignment"
        print_info "Service will use connection string authentication"
    fi
    
    print_success "Azure Communication Services deployment completed"
    print_info "Connection string can be used with Nodemailer or ACS SDK"
    
    return 0
}

# Run deployment if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_communication_service
fi
