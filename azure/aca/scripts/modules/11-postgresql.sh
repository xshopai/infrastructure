#!/bin/bash

# =============================================================================
# Azure PostgreSQL Flexible Server Deployment Module
# =============================================================================
# Creates an Azure PostgreSQL Flexible Server for relational data.
#
# Required Environment Variables:
#   - POSTGRES_SERVER: Name of the PostgreSQL server
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Optional Environment Variables:
#   - POSTGRES_ADMIN_USER: Admin username (default: pgadmin)
#   - POSTGRES_ADMIN_PASSWORD: Admin password (auto-generated if not set)
#
# Exports:
#   - POSTGRES_HOST: PostgreSQL server hostname
#   - POSTGRES_ADMIN_USER: Admin username
#   - POSTGRES_ADMIN_PASSWORD: Admin password
#   - POSTGRES_SERVER_CONNECTION: JDBC connection string
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_postgresql() {
    print_header "Creating Azure PostgreSQL Flexible Server"
    
    # Validate required variables
    validate_required_vars "POSTGRES_SERVER" "RESOURCE_GROUP" "LOCATION" || return 1
    
    print_warning "This may take 5-15 minutes..."
    
    # Generate credentials if not provided
    export POSTGRES_ADMIN_USER="${POSTGRES_ADMIN_USER:-pgadmin}"
    if [ -z "$POSTGRES_ADMIN_PASSWORD" ]; then
        export POSTGRES_ADMIN_PASSWORD="PgShop$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')!"
    fi
    
    # Check if already exists
    if az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "PostgreSQL Server already exists: $POSTGRES_SERVER"
    else
        # Create PostgreSQL Flexible Server with General Purpose tier for production
        # D2ds_v4: 2 vCores, 8 GB RAM, high availability capable
        if az postgres flexible-server create \
            --name "$POSTGRES_SERVER" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --admin-user "$POSTGRES_ADMIN_USER" \
            --admin-password "$POSTGRES_ADMIN_PASSWORD" \
            --sku-name Standard_B1ms \
            --tier Burstable \
            --storage-size 32 \
            --version "15" \
            --public-access 0.0.0.0 \
            --yes \
            --output none 2>&1; then
            print_success "PostgreSQL Server created: $POSTGRES_SERVER"
        else
            print_error "Failed to create PostgreSQL Server: $POSTGRES_SERVER"
            return 1
        fi
    fi
    
    # Get PostgreSQL hostname
    export POSTGRES_HOST=$(az postgres flexible-server show \
        --name "$POSTGRES_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --query fullyQualifiedDomainName -o tsv)
    
    if [ -z "$POSTGRES_HOST" ]; then
        print_error "Failed to retrieve PostgreSQL hostname"
        return 1
    fi
    
    # Build JDBC connection string (server-level, without database)
    export POSTGRES_SERVER_CONNECTION="jdbc:postgresql://${POSTGRES_HOST}:5432/?sslmode=require&user=${POSTGRES_ADMIN_USER}&password=${POSTGRES_ADMIN_PASSWORD}"
    
    print_info "PostgreSQL Host: $POSTGRES_HOST"
    print_info "PostgreSQL Admin: $POSTGRES_ADMIN_USER"
    print_success "PostgreSQL Server configured"
    
    # Configure firewall to allow Azure services
    print_info "Configuring PostgreSQL firewall rules..."
    az postgres flexible-server firewall-rule create \
        --name "$POSTGRES_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --rule-name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none 2>/dev/null || print_warning "Firewall rule may already exist"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_postgresql
fi
