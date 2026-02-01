#!/bin/bash

# =============================================================================
# Module 04: PostgreSQL Databases
# =============================================================================
# Deploys PostgreSQL instances for services:
# - audit-service (port 5434)
# - order-processor-service (port 5435)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying PostgreSQL Databases"

POSTGRES_IMAGE="postgres:16"

ensure_image "$POSTGRES_IMAGE"

# =============================================================================
# PostgreSQL for Audit Service (port 5434)
# =============================================================================
print_subheader "PostgreSQL for Audit Service"

AUDIT_PG_CONTAINER="xshopai-audit-postgres"
AUDIT_PG_PORT="5434"
AUDIT_PG_DB="audit_service_db"
AUDIT_PG_USER="${AUDIT_PG_USER:-admin}"
AUDIT_PG_PASS="${AUDIT_PG_PASS:-admin123}"

if is_container_running "$AUDIT_PG_CONTAINER"; then
    print_info "Audit PostgreSQL is already running"
else
    remove_container "$AUDIT_PG_CONTAINER"
    
    docker run -d \
        --name "$AUDIT_PG_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${AUDIT_PG_PORT}:5432" \
        -e POSTGRES_DB="$AUDIT_PG_DB" \
        -e POSTGRES_USER="$AUDIT_PG_USER" \
        -e POSTGRES_PASSWORD="$AUDIT_PG_PASS" \
        -v xshopai_audit_postgres_data:/var/lib/postgresql/data \
        --health-cmd "pg_isready -U $AUDIT_PG_USER -d $AUDIT_PG_DB" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$POSTGRES_IMAGE"
    
    print_success "Audit PostgreSQL started on port $AUDIT_PG_PORT"
fi

# =============================================================================
# PostgreSQL for Order Processor Service (port 5435)
# =============================================================================
print_subheader "PostgreSQL for Order Processor Service"

ORDER_PROC_PG_CONTAINER="xshopai-order-processor-postgres"
ORDER_PROC_PG_PORT="5435"
ORDER_PROC_PG_DB="order_processor_db"
ORDER_PROC_PG_USER="${ORDER_PROC_PG_USER:-postgres}"
ORDER_PROC_PG_PASS="${ORDER_PROC_PG_PASS:-postgres}"

if is_container_running "$ORDER_PROC_PG_CONTAINER"; then
    print_info "Order Processor PostgreSQL is already running"
else
    remove_container "$ORDER_PROC_PG_CONTAINER"
    
    docker run -d \
        --name "$ORDER_PROC_PG_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${ORDER_PROC_PG_PORT}:5432" \
        -e POSTGRES_DB="$ORDER_PROC_PG_DB" \
        -e POSTGRES_USER="$ORDER_PROC_PG_USER" \
        -e POSTGRES_PASSWORD="$ORDER_PROC_PG_PASS" \
        -v xshopai_order_processor_postgres_data:/var/lib/postgresql/data \
        --health-cmd "pg_isready -U $ORDER_PROC_PG_USER -d $ORDER_PROC_PG_DB" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$POSTGRES_IMAGE"
    
    print_success "Order Processor PostgreSQL started on port $ORDER_PROC_PG_PORT"
fi

# Wait for PostgreSQL instances
print_step "Waiting for PostgreSQL instances to be ready..."
sleep 5

wait_for_container "$AUDIT_PG_CONTAINER" 30
wait_for_container "$ORDER_PROC_PG_CONTAINER" 30

# =============================================================================
# Summary
# =============================================================================
print_header "PostgreSQL Databases Deployed"

echo -e "\n${CYAN}Connection Strings:${NC}"
echo -e "  Audit:          ${GREEN}postgresql://${AUDIT_PG_USER}:${AUDIT_PG_PASS}@localhost:${AUDIT_PG_PORT}/${AUDIT_PG_DB}${NC}"
echo -e "  Order Processor: ${GREEN}postgresql://${ORDER_PROC_PG_USER}:${ORDER_PROC_PG_PASS}@localhost:${ORDER_PROC_PG_PORT}/${ORDER_PROC_PG_DB}${NC}"

print_success "PostgreSQL deployment complete"
