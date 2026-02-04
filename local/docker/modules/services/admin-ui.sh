#!/bin/bash

# =============================================================================
# Admin UI Deployment
# =============================================================================
# Service: admin-ui
# Port: 3001
# Technology: React (served via nginx)
# Backend: admin-service (port 8003)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="admin-ui"
SERVICE_PORT="3001"

# Deploy admin-ui
deploy_frontend "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e REACT_APP_ADMIN_SERVICE_URL=http://localhost:8003 \
     -e REACT_APP_AUTH_SERVICE_URL=http://localhost:8004"

# Summary
echo -e "\n${CYAN}Admin UI:${NC}"
echo -e "  Application:    ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Admin Backend:  ${GREEN}http://localhost:8003${NC}"
