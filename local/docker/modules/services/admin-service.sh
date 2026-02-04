#!/bin/bash

# =============================================================================
# Admin Service Deployment
# =============================================================================
# Service: admin-service
# Port: 8003
# Technology: Node.js/Express
# Database: None (proxies to other services)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="admin-service"
SERVICE_PORT="8003"

# Deploy admin-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e AUTH_SERVICE_URL=http://xshopai-auth-service:8004 \
     -e USER_SERVICE_URL=http://xshopai-user-service:8002 \
     -e PRODUCT_SERVICE_URL=http://xshopai-product-service:8001"

# Summary
echo -e "\n${CYAN}Admin Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
