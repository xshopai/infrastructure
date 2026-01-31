#!/bin/bash

# =============================================================================
# Azure SQL Server Deployment Module
# =============================================================================
# Creates an Azure SQL Server with Azure AD-only authentication.
#
# Required Environment Variables:
#   - SQL_SERVER: Name of the SQL server
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Exports:
#   - SQL_HOST: SQL server hostname
#   - SQL_SERVER_CONNECTION: Connection string (using AD auth)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_sql_server() {
    print_header "Creating Azure SQL Server"
    
    # Validate required variables
    validate_required_vars "SQL_SERVER" "RESOURCE_GROUP" "LOCATION" || return 1
    
    print_warning "This may take 2-5 minutes..."
    
    # Get current user info for Azure AD admin
    local SQL_AD_ADMIN_SID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    local SQL_AD_ADMIN_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "")
    
    if [ -z "$SQL_AD_ADMIN_SID" ] || [ -z "$SQL_AD_ADMIN_NAME" ]; then
        print_error "Failed to get current user info for Azure AD admin"
        return 1
    fi
    
    # Check if already exists
    if az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "SQL Server already exists: $SQL_SERVER"
    else
        # Create SQL Server with Azure AD-only authentication
        if az sql server create \
            --name "$SQL_SERVER" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --enable-ad-only-auth \
            --external-admin-principal-type User \
            --external-admin-sid "$SQL_AD_ADMIN_SID" \
            --external-admin-name "$SQL_AD_ADMIN_NAME" \
            --output none 2>&1; then
            print_success "SQL Server created: $SQL_SERVER"
        else
            print_error "Failed to create SQL Server: $SQL_SERVER"
            return 1
        fi
    fi
    
    # Get SQL hostname
    export SQL_HOST=$(az sql server show \
        --name "$SQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName -o tsv)
    
    if [ -z "$SQL_HOST" ]; then
        print_error "Failed to retrieve SQL Server hostname"
        return 1
    fi
    
    # Build connection string (using Azure AD authentication)
    export SQL_SERVER_CONNECTION="Server=$SQL_HOST;Authentication=Active Directory Default;TrustServerCertificate=True;Encrypt=True"
    
    print_info "SQL Host: $SQL_HOST"
    print_info "SQL Auth: Azure AD-only"
    print_success "SQL Server configured"
    
    # Configure firewall to allow Azure services
    print_info "Configuring SQL Server firewall rules..."
    az sql server firewall-rule create \
        --name "AllowAzureServices" \
        --server "$SQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none 2>/dev/null || print_warning "Firewall rule may already exist"
    
    print_success "SQL Server ready: $SQL_HOST"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_sql_server
fi
