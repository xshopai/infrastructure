#!/bin/bash

# =============================================================================
# User Service Deployment
# =============================================================================
# Service: user-service
# Port: 8002
# Technology: Node.js/Express
# Database: MongoDB (port 27018)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="user-service"
SERVICE_PORT="8002"
DB_HOST="xshopai-user-mongodb"
DB_PORT="27017"  # Internal MongoDB port (external is 27018)

# Deploy user-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e MONGODB_HOST=$DB_HOST -e MONGODB_PORT=$DB_PORT" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}User Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
