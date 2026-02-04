#!/bin/bash

# =============================================================================
# Web BFF (Backend For Frontend) Deployment
# =============================================================================
# Service: web-bff
# Port: 8014
# Technology: Node.js/TypeScript/Express
# Database: None (aggregates backend services)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="web-bff"
SERVICE_PORT="8014"

# Deploy web-bff
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e AUTH_SERVICE_URL=http://xshopai-auth-service:8004 \
     -e USER_SERVICE_URL=http://xshopai-user-service:8002 \
     -e PRODUCT_SERVICE_URL=http://xshopai-product-service:8001 \
     -e CART_SERVICE_URL=http://xshopai-cart-service:8008 \
     -e ORDER_SERVICE_URL=http://xshopai-order-service:8006 \
     -e REVIEW_SERVICE_URL=http://xshopai-review-service:8010 \
     -e INVENTORY_SERVICE_URL=http://xshopai-inventory-service:8005" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Web BFF:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  This service aggregates:"
echo -e "    - Auth Service"
echo -e "    - User Service"
echo -e "    - Product Service"
echo -e "    - Cart Service"
echo -e "    - Order Service"
echo -e "    - Review Service"
echo -e "    - Inventory Service"
