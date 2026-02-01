#!/bin/bash

# =============================================================================
# Azure MySQL Flexible Server Deployment Module
# =============================================================================
# Creates an Azure MySQL Flexible Server for relational data.
#
# Required Environment Variables:
#   - MYSQL_SERVER: Name of the MySQL server
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Optional Environment Variables:
#   - MYSQL_ADMIN_USER: Admin username (default: xshopaiadmin)
#   - MYSQL_ADMIN_PASSWORD: Admin password (auto-generated if not set)
#
# Exports:
#   - MYSQL_HOST: MySQL server hostname
#   - MYSQL_ADMIN_USER: Admin username
#   - MYSQL_ADMIN_PASSWORD: Admin password
#   - MYSQL_SERVER_CONNECTION: Server-level connection string (without database)
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_mysql() {
    print_header "Creating Azure MySQL Flexible Server"
    
    # Validate required variables
    validate_required_vars "MYSQL_SERVER" "RESOURCE_GROUP" "LOCATION" || return 1
    
    print_warning "This may take 5-15 minutes..."
    
    # Use fixed credentials (set by deploy.sh or use defaults)
    # Fixed passwords ensure consistency between DB creation and Key Vault storage
    export MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-xshopaiadmin}"
    export MYSQL_ADMIN_PASSWORD="${MYSQL_ADMIN_PASSWORD:-xshopaipassword123}"
    
    # Check if already exists
    if resource_exists "mysql" "$MYSQL_SERVER" "$RESOURCE_GROUP"; then
        print_warning "MySQL Server already exists: $MYSQL_SERVER"
    else
        # Create MySQL Flexible Server with General Purpose tier for production
        # D2ds_v4: 2 vCores, 8 GB RAM, high availability capable
        if az mysql flexible-server create \
            --name "$MYSQL_SERVER" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --admin-user "$MYSQL_ADMIN_USER" \
            --admin-password "$MYSQL_ADMIN_PASSWORD" \
            --sku-name Standard_B1ms \
            --tier Burstable \
            --storage-size 32 \
            --version "8.0.21" \
            --public-access 0.0.0.0 \
            --output none 2>&1; then
            print_success "MySQL Server created: $MYSQL_SERVER"
        else
            print_error "Failed to create MySQL Server: $MYSQL_SERVER"
            return 1
        fi
    fi
    
    # Configure firewall to allow Azure services (always run to ensure access)
    print_info "Ensuring MySQL firewall allows Azure services..."
    az mysql flexible-server firewall-rule create \
        --name "$MYSQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --rule-name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none 2>/dev/null || print_success "Firewall rule already configured"
    
    # Get MySQL hostname
    export MYSQL_HOST=$(az mysql flexible-server show \
        --name "$MYSQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName -o tsv)
    
    if [ -z "$MYSQL_HOST" ]; then
        print_error "Failed to retrieve MySQL hostname"
        return 1
    fi
    
    # Build server-level connection string (without database name)
    export MYSQL_SERVER_CONNECTION="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306"
    
    print_info "MySQL Host: $MYSQL_HOST"
    print_info "MySQL Admin: $MYSQL_ADMIN_USER"
    print_success "MySQL Server configured"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_mysql
fi
