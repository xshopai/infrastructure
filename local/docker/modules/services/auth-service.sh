#!/bin/bash

# =============================================================================
# Auth Service Deployment
# =============================================================================
# Service: auth-service
# Port: 8004
# Technology: Node.js/Express
# Database: MongoDB (port 27017)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="auth-service"
SERVICE_PORT="8004"
DB_HOST="xshopai-auth-mongodb"
DB_PORT="27017"

# Deploy auth-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e MONGODB_HOST=$DB_HOST -e MONGODB_PORT=$DB_PORT" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Auth Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
