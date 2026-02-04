#!/bin/bash

# =============================================================================
# Customer UI Deployment
# =============================================================================
# Service: customer-ui
# Port: 3000
# Technology: React (served via nginx)
# Backend: web-bff (port 8014)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="customer-ui"
SERVICE_PORT="3000"

# Deploy customer-ui
deploy_frontend "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e REACT_APP_BFF_URL=http://localhost:8014 \
     -e REACT_APP_WS_URL=ws://localhost:8013"

# Summary
echo -e "\n${CYAN}Customer UI:${NC}"
echo -e "  Application:  ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  BFF Backend:  ${GREEN}http://localhost:8014${NC}"
