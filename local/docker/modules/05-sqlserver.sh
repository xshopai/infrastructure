#!/bin/bash

# =============================================================================
# Module 05: SQL Server Databases
# =============================================================================
# Deploys SQL Server instances for services:
# - order-service (port 1434)
# - payment-service (port 1433)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying SQL Server Databases"

SQLSERVER_IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
SQLSERVER_SA_PASSWORD="${SQLSERVER_SA_PASSWORD:-Admin123!}"

ensure_image "$SQLSERVER_IMAGE"

# =============================================================================
# SQL Server for Payment Service (port 1433)
# =============================================================================
print_subheader "SQL Server for Payment Service"

PAYMENT_SQL_CONTAINER="xshopai-payment-sqlserver"
PAYMENT_SQL_PORT="1433"
PAYMENT_SQL_DB="payment_service_db"

if is_container_running "$PAYMENT_SQL_CONTAINER"; then
    print_info "Payment SQL Server is already running"
else
    remove_container "$PAYMENT_SQL_CONTAINER"
    
    docker run -d \
        --name "$PAYMENT_SQL_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${PAYMENT_SQL_PORT}:1433" \
        -e "ACCEPT_EULA=Y" \
        -e "SA_PASSWORD=$SQLSERVER_SA_PASSWORD" \
        -e "MSSQL_PID=Developer" \
        -v xshopai_payment_sqlserver_data:/var/opt/mssql \
        --health-cmd "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '$SQLSERVER_SA_PASSWORD' -Q 'SELECT 1' -C -b" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 10 \
        "$SQLSERVER_IMAGE"
    
    print_success "Payment SQL Server started on port $PAYMENT_SQL_PORT"
fi

# =============================================================================
# SQL Server for Order Service (port 1434)
# =============================================================================
print_subheader "SQL Server for Order Service"

ORDER_SQL_CONTAINER="xshopai-order-sqlserver"
ORDER_SQL_PORT="1434"
ORDER_SQL_DB="order_service_db"

if is_container_running "$ORDER_SQL_CONTAINER"; then
    print_info "Order SQL Server is already running"
else
    remove_container "$ORDER_SQL_CONTAINER"
    
    docker run -d \
        --name "$ORDER_SQL_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${ORDER_SQL_PORT}:1433" \
        -e "ACCEPT_EULA=Y" \
        -e "SA_PASSWORD=$SQLSERVER_SA_PASSWORD" \
        -e "MSSQL_PID=Developer" \
        -v xshopai_order_sqlserver_data:/var/opt/mssql \
        --health-cmd "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '$SQLSERVER_SA_PASSWORD' -Q 'SELECT 1' -C -b" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 10 \
        "$SQLSERVER_IMAGE"
    
    print_success "Order SQL Server started on port $ORDER_SQL_PORT"
fi

# Wait for SQL Server instances (they take longer to start)
print_step "Waiting for SQL Server instances to be ready (this may take up to 60 seconds)..."
sleep 10

wait_for_container "$PAYMENT_SQL_CONTAINER" 60
wait_for_container "$ORDER_SQL_CONTAINER" 60

# =============================================================================
# Create Databases
# =============================================================================
print_subheader "Creating Databases"

# Wait a bit more for SQL Server to fully initialize
sleep 5

# Create Payment Service Database
print_step "Creating payment_service_db..."
docker exec "$PAYMENT_SQL_CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SQLSERVER_SA_PASSWORD" -C \
    -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'payment_service_db') CREATE DATABASE payment_service_db" \
    2>/dev/null && print_success "Created payment_service_db" || print_warning "payment_service_db may already exist"

# Create Order Service Database
print_step "Creating order_service_db..."
docker exec "$ORDER_SQL_CONTAINER" /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$SQLSERVER_SA_PASSWORD" -C \
    -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'order_service_db') CREATE DATABASE order_service_db" \
    2>/dev/null && print_success "Created order_service_db" || print_warning "order_service_db may already exist"

# =============================================================================
# Summary
# =============================================================================
print_header "SQL Server Databases Deployed"

echo -e "\n${CYAN}Connection Strings:${NC}"
echo -e "  Payment: ${GREEN}Server=localhost,${PAYMENT_SQL_PORT};Database=${PAYMENT_SQL_DB};User Id=sa;Password=${SQLSERVER_SA_PASSWORD};TrustServerCertificate=True${NC}"
echo -e "  Order:   ${GREEN}Server=localhost,${ORDER_SQL_PORT};Database=${ORDER_SQL_DB};User Id=sa;Password=${SQLSERVER_SA_PASSWORD};TrustServerCertificate=True${NC}"

print_success "SQL Server deployment complete"
