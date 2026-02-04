#!/bin/bash

# =============================================================================
# Order Service Deployment
# =============================================================================
# Service: order-service
# Port: 8006
# Technology: .NET 8/ASP.NET Core
# Database: SQL Server (port 1434)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="order-service"
SERVICE_PORT="8006"
DB_HOST="xshopai-order-sqlserver"
DB_PORT="1433"  # Internal SQL Server port (external is 1434)

# Connection string
CONNECTION_STRING="Server=${DB_HOST},${DB_PORT};Database=order_service_db;User Id=sa;Password=Admin123!;TrustServerCertificate=True"

# Deploy order-service
deploy_dotnet_service "$SERVICE_NAME" "$SERVICE_PORT" "$CONNECTION_STRING" \
    "-e RABBITMQ_HOST=xshopai-rabbitmq \
     -e RABBITMQ_PORT=5672" \
    ".dapr"

# Summary
echo -e "\n${CYAN}Order Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Swagger:      ${GREEN}http://localhost:${SERVICE_PORT}/swagger${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
