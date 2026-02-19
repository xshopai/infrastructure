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
#   - MYSQL_ADMIN_USER: Admin username (default: mysqladmin)
#   - MYSQL_ADMIN_PASSWORD: Admin password (unique per deployment)
#
# Exports:
#   - MYSQL_HOST: MySQL server hostname
#   - MYSQL_ADMIN_USER: Admin username
#   - MYSQL_ADMIN_PASSWORD: Admin password
#   - MYSQL_SERVER_CONNECTION: Server-level connection string
# =============================================================================

set -e

deploy_mysql() {
    print_header "Creating Azure MySQL Flexible Server"
    
    # Validate required variables
    validate_required_vars "MYSQL_SERVER" "RESOURCE_GROUP" "LOCATION" || return 1
    
    # Use fixed credentials
    export MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-mysqladmin}"
    export MYSQL_ADMIN_PASSWORD="${MYSQL_ADMIN_PASSWORD:-${DB_ADMIN_PASSWORD}}"
    
    # Check if already exists - skip quickly if so
    if az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "MySQL Server exists: $MYSQL_SERVER (skipping creation)"
    else
        print_warning "This may take 5-15 minutes..."
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
    
    # Get MySQL hostname
    export MYSQL_HOST=$(az mysql flexible-server show \
        --name "$MYSQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName -o tsv 2>/dev/null)
    
    if [ -z "$MYSQL_HOST" ]; then
        print_error "Failed to retrieve MySQL hostname"
        return 1
    fi
    
    # Configure firewall (idempotent)
    az mysql flexible-server firewall-rule create \
        --name "$MYSQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --rule-name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none 2>/dev/null || true
    
    # Add developer's IP for dev environment (allows local seeding, testing)
    if [[ "$ENVIRONMENT" == "dev" ]]; then
        local dev_ip
        dev_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
        if [[ -n "$dev_ip" && "$dev_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            az mysql flexible-server firewall-rule create \
                --name "$MYSQL_SERVER" \
                --resource-group "$RESOURCE_GROUP" \
                --rule-name "developer-ip-${dev_ip//./-}" \
                --start-ip-address "$dev_ip" \
                --end-ip-address "$dev_ip" \
                --output none 2>/dev/null || true
            print_info "Added developer IP to firewall: $dev_ip"
        fi
    fi
    
    # Create service databases
    for db_name in "inventory_service_db" "cart_service_db" "chat_service_db"; do
        if ! az mysql flexible-server db show \
            --resource-group "$RESOURCE_GROUP" \
            --server-name "$MYSQL_SERVER" \
            --database-name "$db_name" &>/dev/null; then
            az mysql flexible-server db create \
                --resource-group "$RESOURCE_GROUP" \
                --server-name "$MYSQL_SERVER" \
                --database-name "$db_name" \
                --output none 2>/dev/null || true
        fi
    done
    
    # Build connection string
    export MYSQL_SERVER_CONNECTION="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306"
    
    print_info "MySQL Host: $MYSQL_HOST"
    print_success "MySQL Server ready"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_mysql
fi
