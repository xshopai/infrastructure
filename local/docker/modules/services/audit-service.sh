#!/bin/bash

# =============================================================================
# Audit Service Deployment
# =============================================================================
# Service: audit-service
# Port: 8012
# Technology: Node.js/Express
# Database: PostgreSQL (port 5434)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="audit-service"
SERVICE_PORT="8012"
DB_HOST="xshopai-audit-postgres"
DB_PORT="5432"  # Internal PostgreSQL port (external is 5434)

# Deploy audit-service
deploy_nodejs_service "$SERVICE_NAME" "$SERVICE_PORT" \
    "-e POSTGRES_HOST=$DB_HOST \
     -e POSTGRES_PORT=$DB_PORT \
     -e POSTGRES_USER=postgres \
     -e POSTGRES_PASSWORD=postgres123 \
     -e POSTGRES_DB=audit_service_db" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Audit Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
