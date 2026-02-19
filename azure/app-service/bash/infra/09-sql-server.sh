#!/bin/bash

# =============================================================================
# Azure SQL Server Deployment Module
# =============================================================================
# Creates an Azure SQL Server with SQL authentication (username/password).
#
# Required Environment Variables:
#   - SQL_SERVER: Name of the SQL server
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Optional Environment Variables:
#   - SQL_ADMIN_USER: SQL admin username (default: sqladmin)
#   - SQL_ADMIN_PASSWORD: SQL admin password (from DB_ADMIN_PASSWORD)
#
# Exports:
#   - SQL_HOST: SQL server hostname
#   - SQL_ADMIN_USER: Admin username
#   - SQL_ADMIN_PASSWORD: Admin password
#   - SQL_SERVER_CONNECTION: Connection string
# =============================================================================

set -e

deploy_sql_server() {
    print_header "Creating Azure SQL Server"
    
    # Validate required variables
    validate_required_vars "SQL_SERVER" "RESOURCE_GROUP" "LOCATION" || return 1
    
    # Use fixed credentials (set by deploy.sh or use defaults)
    export SQL_ADMIN_USER="${SQL_ADMIN_USER:-sqladmin}"
    export SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-${DB_ADMIN_PASSWORD}}"
    
    # Check if already exists
    if az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "SQL Server already exists: $SQL_SERVER (skipping creation)"
    else
        print_warning "This may take 2-5 minutes..."
        # Create SQL Server with SQL authentication (username/password)
        if az sql server create \
            --name "$SQL_SERVER" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --admin-user "$SQL_ADMIN_USER" \
            --admin-password "$SQL_ADMIN_PASSWORD" \
            --output none 2>&1; then
            print_success "SQL Server created: $SQL_SERVER"
        else
            print_error "Failed to create SQL Server: $SQL_SERVER"
            return 1
        fi
    fi
    
    # Configure firewall to allow Azure services
    print_info "Configuring firewall..."
    az sql server firewall-rule create \
        --name "AllowAzureServices" \
        --server "$SQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none 2>/dev/null || true
    
    # Get SQL hostname
    export SQL_HOST=$(az sql server show \
        --name "$SQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName -o tsv)
    
    if [ -z "$SQL_HOST" ]; then
        print_error "Failed to retrieve SQL Server hostname"
        return 1
    fi
    
    # Build connection string
    export SQL_SERVER_CONNECTION="Server=$SQL_HOST;User Id=$SQL_ADMIN_USER;Password=$SQL_ADMIN_PASSWORD;Encrypt=True;TrustServerCertificate=True"
    
    print_info "SQL Host: $SQL_HOST"
    print_success "SQL Server ready"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_sql_server
fi
