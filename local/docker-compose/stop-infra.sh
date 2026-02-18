#!/bin/bash
# =============================================================================
# xshopai - Stop Infrastructure Services
# =============================================================================
# This script stops all infrastructure and database services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Stopping xshopai Infrastructure${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo -e "${YELLOW}Stopping infrastructure services...${NC}"
$COMPOSE_CMD -f docker-compose.infrastructure.yml down

echo ""
echo -e "${YELLOW}Stopping database services...${NC}"
$COMPOSE_CMD -f docker-compose.databases.yml down

echo ""
echo -e "${GREEN}✅ All infrastructure services stopped!${NC}"
echo ""
echo -e "${YELLOW}Note: Data is preserved in Docker volumes.${NC}"
echo -e "${YELLOW}To remove volumes and delete all data, run:${NC}"
echo -e "  docker-compose -f docker-compose.infrastructure.yml down --volumes"
echo -e "  docker-compose -f docker-compose.databases.yml down --volumes"
echo ""
