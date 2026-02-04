#!/bin/bash

# =============================================================================
# Inventory Service Deployment
# =============================================================================
# Service: inventory-service
# Port: 8005
# Technology: Python/FastAPI
# Database: MySQL (port 3306)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="inventory-service"
SERVICE_PORT="8005"
DB_HOST="xshopai-inventory-mysql"
DB_PORT="3306"

# Deploy inventory-service
deploy_python_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e MYSQL_HOST=$DB_HOST \
     -e MYSQL_PORT=$DB_PORT \
     -e MYSQL_USER=inventory \
     -e MYSQL_PASSWORD=inventory123 \
     -e MYSQL_DATABASE=inventory_service_db" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Inventory Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  API Docs:     ${GREEN}http://localhost:${SERVICE_PORT}/docs${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
