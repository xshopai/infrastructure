#!/bin/bash

# =============================================================================
# Cart Service Deployment
# =============================================================================
# Service: cart-service
# Port: 8008
# Technology: Java/Quarkus
# Database: Redis (port 6379)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="cart-service"
SERVICE_PORT="8008"
REDIS_HOST="xshopai-redis"
REDIS_PORT="6379"

# Deploy cart-service (Quarkus)
deploy_java_service "$SERVICE_NAME" "$SERVICE_PORT" "quarkus" \
    "-e REDIS_HOST=$REDIS_HOST \
     -e REDIS_PORT=$REDIS_PORT \
     -e REDIS_PASSWORD=redis123 \
     -e PRODUCT_SERVICE_URL=http://xshopai-product-service:8001" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Cart Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Redis Cache:  ${GREEN}${REDIS_HOST}:${REDIS_PORT}${NC}"
