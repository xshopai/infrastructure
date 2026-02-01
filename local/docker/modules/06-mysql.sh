#!/bin/bash

# =============================================================================
# Module 06: MySQL Database
# =============================================================================
# Deploys MySQL instance for:
# - inventory-service (port 3306)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying MySQL Database"

MYSQL_IMAGE="mysql:8"
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-inventory_root_pass_123}"

ensure_image "$MYSQL_IMAGE"

# =============================================================================
# MySQL for Inventory Service (port 3306)
# =============================================================================
print_subheader "MySQL for Inventory Service"

INVENTORY_MYSQL_CONTAINER="xshopai-inventory-mysql"
INVENTORY_MYSQL_PORT="3306"
INVENTORY_MYSQL_DB="inventory_service_db"
INVENTORY_MYSQL_USER="${INVENTORY_MYSQL_USER:-admin}"
INVENTORY_MYSQL_PASS="${INVENTORY_MYSQL_PASS:-admin123}"

if is_container_running "$INVENTORY_MYSQL_CONTAINER"; then
    print_info "Inventory MySQL is already running"
else
    remove_container "$INVENTORY_MYSQL_CONTAINER"
    
    docker run -d \
        --name "$INVENTORY_MYSQL_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${INVENTORY_MYSQL_PORT}:3306" \
        -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASS" \
        -e MYSQL_DATABASE="$INVENTORY_MYSQL_DB" \
        -e MYSQL_USER="$INVENTORY_MYSQL_USER" \
        -e MYSQL_PASSWORD="$INVENTORY_MYSQL_PASS" \
        -v xshopai_inventory_mysql_data:/var/lib/mysql \
        --health-cmd "mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASS" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 10 \
        "$MYSQL_IMAGE"
    
    print_success "Inventory MySQL started on port $INVENTORY_MYSQL_PORT"
fi

# Wait for MySQL (it takes longer to initialize)
print_step "Waiting for MySQL to be ready (this may take up to 60 seconds)..."
sleep 10

wait_for_container "$INVENTORY_MYSQL_CONTAINER" 60

# =============================================================================
# Summary
# =============================================================================
print_header "MySQL Database Deployed"

echo -e "\n${CYAN}Connection Strings:${NC}"
echo -e "  Inventory: ${GREEN}mysql://${INVENTORY_MYSQL_USER}:${INVENTORY_MYSQL_PASS}@localhost:${INVENTORY_MYSQL_PORT}/${INVENTORY_MYSQL_DB}${NC}"
echo -e "  Root:      ${GREEN}mysql://root:${MYSQL_ROOT_PASS}@localhost:${INVENTORY_MYSQL_PORT}/${INVENTORY_MYSQL_DB}${NC}"

print_success "MySQL deployment complete"
