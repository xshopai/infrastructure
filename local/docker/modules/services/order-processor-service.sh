#!/bin/bash

# =============================================================================
# Order Processor Service Deployment
# =============================================================================
# Service: order-processor-service
# Port: 8007
# Technology: Java/Spring Boot
# Database: PostgreSQL (port 5435)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# Service configuration
SERVICE_NAME="order-processor-service"
SERVICE_PORT="8007"
DB_HOST="xshopai-order-processor-postgres"
DB_PORT="5432"  # Internal PostgreSQL port (external is 5435)

# Deploy order-processor-service (Spring Boot)
deploy_java_service "$SERVICE_NAME" "$SERVICE_PORT" "spring" \
    "-e SPRING_DATASOURCE_URL=jdbc:postgresql://${DB_HOST}:${DB_PORT}/order_processor_db \
     -e SPRING_DATASOURCE_USERNAME=postgres \
     -e SPRING_DATASOURCE_PASSWORD=postgres123 \
     -e RABBITMQ_HOST=xshopai-rabbitmq \
     -e RABBITMQ_PORT=5672" \
    ".dapr/components"

# Summary
echo -e "\n${CYAN}Order Processor Service:${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:${SERVICE_PORT}${NC}"
echo -e "  Database:     ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
