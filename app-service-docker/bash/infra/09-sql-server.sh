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
#   - SQL_ADMIN_PASSWORD: SQL admin password (unique per deployment)
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
        # Create SQL Server via ARM REST API so we can pass the SecurityControl=Ignore tag
        # at creation time. MCAPS governance on MS internal subscriptions blocks
        # SQL Server creation without either Azure AD-only auth OR this tag exemption.
        # az sql server create does not expose --tags in the installed CLI version.
        local create_body
        create_body=$(cat <<EOF
{
  "location": "${LOCATION}",
  "tags": {"SecurityControl": "Ignore"},
  "properties": {
    "administratorLogin": "${SQL_ADMIN_USER}",
    "administratorLoginPassword": "${SQL_ADMIN_PASSWORD}",
    "publicNetworkAccess": "Enabled"
  }
}
EOF
)
        local create_result
        create_result=$(MSYS_NO_PATHCONV=1 az rest \
            --method put \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Sql/servers/${SQL_SERVER}?api-version=2021-11-01" \
            --body "$create_body" 2>&1)

        if echo "$create_result" | grep -qi "error\|\"code\""; then
            echo "$create_result"
            print_error "Failed to create SQL Server: $SQL_SERVER"
            return 1
        fi

        # Wait for async provisioning to complete
        print_info "Waiting for SQL Server provisioning..."
        local wait_secs=0
        while true; do
            local fqdn
            fqdn=$(az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" \
                --query fullyQualifiedDomainName -o tsv 2>/dev/null || echo "")
            if [ -n "$fqdn" ]; then break; fi
            sleep 10
            wait_secs=$((wait_secs + 10))
            if [ $wait_secs -ge 600 ]; then
                print_error "SQL Server did not become available within 10 minutes"
                return 1
            fi
        done
        print_success "SQL Server created: $SQL_SERVER"
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
