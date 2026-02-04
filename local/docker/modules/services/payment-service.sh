#!/bin/bash

# =============================================================================
# Payment Service Deployment
# =============================================================================
# Service: payment-service
# Port: 8009
# Technology: .NET 8/ASP.NET Core
# Database: SQL Server (port 1433)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="payment-service"
SERVICE_PORT="8009"
DB_HOST="xshopai-payment-sqlserver"
DB_PORT="1433"

# Connection string
CONNECTION_STRING="Server=${DB_HOST},${DB_PORT};Database=payment_service_db;User Id=sa;Password=Admin123!;TrustServerCertificate=True"

# Deploy payment-service
deploy_dotnet_service "$SERVICE_NAME" "$SERVICE_PORT" "$CONNECTION_STRING" \
    "-e RABBITMQ_HOST=xshopai-rabbitmq \
     -e RABBITMQ_PORT=5672" \
    ".dapr"

# Summary
echo -e "\n${CYAN}Payment Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Swagger:      ${GREEN}http://localhost:${SERVICE_PORT}/swagger${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
