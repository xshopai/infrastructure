#!/bin/bash
# =============================================================================
# xshopai - Start Infrastructure Services
# =============================================================================
# This script starts all required infrastructure services for local development
#
# Services started:
#   - RabbitMQ (Message Broker)
#   - Zipkin (Distributed Tracing)
#   - Mailpit (Email Testing)
#   - All Database Services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Starting xshopai Infrastructure${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}⚠️  docker-compose not found. Trying 'docker compose' instead...${NC}"
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo -e "${CYAN}Starting infrastructure services...${NC}"
$COMPOSE_CMD -f docker-compose.infrastructure.yml up -d

echo ""
echo -e "${CYAN}Starting database services...${NC}"
$COMPOSE_CMD -f docker-compose.databases.yml up -d

echo ""
echo -e "${GREEN}✅ All infrastructure services started!${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${CYAN}Service Endpoints:${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Messaging & Event Bus:${NC}"
echo -e "  RabbitMQ Management: ${GREEN}http://localhost:15672${NC} (admin/admin123)"
echo ""
echo -e "${YELLOW}Observability:${NC}"
echo -e "  Zipkin Tracing:      ${GREEN}http://localhost:9411${NC}"
echo ""
echo -e "${YELLOW}Development Tools:${NC}"
echo -e "  Mailpit (Email):     ${GREEN}http://localhost:8025${NC}"
echo ""
echo -e "${YELLOW}Databases:${NC}"
echo -e "  User MongoDB:        ${GREEN}localhost:27018${NC} (admin/admin123)"
echo -e "  Product MongoDB:     ${GREEN}localhost:27019${NC} (admin/admin123)"
echo -e "  Review MongoDB:      ${GREEN}localhost:27020${NC} (admin/admin123)"
echo -e "  Auth MongoDB:        ${GREEN}localhost:27021${NC} (admin/admin123)"
echo -e "  Audit PostgreSQL:    ${GREEN}localhost:5434${NC} (admin/admin123)"
echo -e "  Order Processor PG:  ${GREEN}localhost:5435${NC} (postgres/postgres)"
echo -e "  Order SQL Server:    ${GREEN}localhost:1434${NC} (sa/Admin123!)"
echo -e "  Payment SQL Server:  ${GREEN}localhost:1433${NC} (sa/Admin123!)"
echo -e "  Inventory MySQL:     ${GREEN}localhost:3306${NC} (admin/admin123)"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${CYAN}To stop all services:${NC}"
echo -e "  ./stop-infra.sh"
echo ""
echo -e "${CYAN}To view logs:${NC}"
echo -e "  docker-compose -f docker-compose.infrastructure.yml logs -f"
echo ""
