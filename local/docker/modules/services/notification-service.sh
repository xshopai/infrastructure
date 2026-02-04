#!/bin/bash

# =============================================================================
# Notification Service Deployment
# =============================================================================
# Service: notification-service
# Port: 8011
# Technology: Node.js/Express
# Database: None
# External: Mailpit SMTP (port 1025)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="notification-service"
SERVICE_PORT="8011"
SMTP_HOST="xshopai-mailpit"
SMTP_PORT="1025"

# Deploy notification-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e SMTP_HOST=$SMTP_HOST \
     -e SMTP_PORT=$SMTP_PORT \
     -e EMAIL_FROM=noreply@xshopai.com" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Notification Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  SMTP Server:  ${GREEN}${SMTP_HOST}:${SMTP_PORT}${NC}"
echo -e "  Mailpit UI:   ${GREEN}http://localhost:8025${NC}"
