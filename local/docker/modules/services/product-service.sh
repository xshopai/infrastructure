#!/bin/bash

# =============================================================================
# Product Service Deployment
# =============================================================================
# Service: product-service
# Port: 8001
# Technology: Python/FastAPI
# Database: MongoDB (port 27019)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="product-service"
SERVICE_PORT="8001"
DB_HOST="xshopai-product-mongodb"
DB_PORT="27017"  # Internal MongoDB port (external is 27019)

# Deploy product-service
deploy_python_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e MONGODB_HOST=$DB_HOST \
     -e MONGODB_PORT=$DB_PORT \
     -e MONGODB_DATABASE=product_service_db" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Product Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  API Docs:     ${GREEN}http://localhost:${SERVICE_PORT}/docs${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
