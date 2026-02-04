#!/bin/bash

# =============================================================================
# Review Service Deployment
# =============================================================================
# Service: review-service
# Port: 8010
# Technology: Node.js/Express
# Database: MongoDB (port 27020)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="review-service"
SERVICE_PORT="8010"
DB_HOST="xshopai-review-mongodb"
DB_PORT="27017"  # Internal MongoDB port (external is 27020)

# Deploy review-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e MONGODB_HOST=$DB_HOST -e MONGODB_PORT=$DB_PORT" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Review Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
