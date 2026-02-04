#!/bin/bash

# =============================================================================
# Chat Service Deployment
# =============================================================================
# Service: chat-service
# Port: 8013
# Technology: Node.js/Express (WebSocket support)
# Database: None (in-memory or Redis for scaling)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="chat-service"
SERVICE_PORT="8013"

# Deploy chat-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e REDIS_HOST=xshopai-redis \
     -e REDIS_PORT=6379"

# Summary
echo -e "\n${CYAN}Chat Service:${NC}"
echo -e "  API Endpoint:     ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  WebSocket:        ${GREEN}ws://localhost:${SERVICE_PORT}${NC}"
