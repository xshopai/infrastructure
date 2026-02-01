#!/bin/bash

# =============================================================================
# xshopai Local Docker Deployment Orchestrator
# =============================================================================
# This is the main entry point for deploying xshopai platform locally using Docker.
# It orchestrates the deployment of all infrastructure, databases, and services.
#
# Architecture:
#   - Modular design: Each resource has its own deployment module
#   - Easy debugging: Run individual modules to troubleshoot specific resources
#   - Sequential execution: Ensures dependencies are met before starting services
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   --all                Deploy everything (default)
#   --infra-only         Deploy only infrastructure (message broker, cache, etc.)
#   --db-only            Deploy only databases
#   --services-only      Deploy only application services (requires DBs running)
#   --frontends-only     Deploy only frontend applications
#   --skip-build         Skip building Docker images (use existing)
#   --clean              Remove all containers and volumes before deploying
#   --help               Show this help message
#
# Examples:
#   ./deploy.sh                    # Deploy everything
#   ./deploy.sh --infra-only       # Deploy only infrastructure
#   ./deploy.sh --skip-build       # Deploy without rebuilding images
#   ./deploy.sh --clean --all      # Clean and redeploy everything
# =============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source common utilities
source "$MODULES_DIR/common.sh"

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------
DEPLOY_INFRA=false
DEPLOY_DBS=false
DEPLOY_SERVICES=false
DEPLOY_FRONTENDS=false
SKIP_BUILD=false
CLEAN_FIRST=false
DEPLOY_ALL=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            DEPLOY_ALL=true
            shift
            ;;
        --infra-only)
            DEPLOY_ALL=false
            DEPLOY_INFRA=true
            shift
            ;;
        --db-only)
            DEPLOY_ALL=false
            DEPLOY_DBS=true
            shift
            ;;
        --services-only)
            DEPLOY_ALL=false
            DEPLOY_SERVICES=true
            shift
            ;;
        --frontends-only)
            DEPLOY_ALL=false
            DEPLOY_FRONTENDS=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            export BUILD_IMAGES=false
            shift
            ;;
        --clean)
            CLEAN_FIRST=true
            shift
            ;;
        --help|-h)
            head -50 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If deploy all, enable all components
if [ "$DEPLOY_ALL" = true ]; then
    DEPLOY_INFRA=true
    DEPLOY_DBS=true
    DEPLOY_SERVICES=true
    DEPLOY_FRONTENDS=true
fi

# Track deployment progress
SCRIPT_START_TIME=$SECONDS
TOTAL_STEPS=0
CURRENT_STEP=0

# Count total steps
[ "$DEPLOY_INFRA" = true ] && TOTAL_STEPS=$((TOTAL_STEPS + 2))
[ "$DEPLOY_DBS" = true ] && TOTAL_STEPS=$((TOTAL_STEPS + 4))
[ "$DEPLOY_SERVICES" = true ] && TOTAL_STEPS=$((TOTAL_STEPS + 4))
[ "$DEPLOY_FRONTENDS" = true ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

print_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local ELAPSED=$((SECONDS - SCRIPT_START_TIME))
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[$CURRENT_STEP/$TOTAL_STEPS] $1${NC} ${CYAN}(${ELAPSED}s elapsed)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# =============================================================================
# Prerequisites Check
# =============================================================================
print_header "xshopai Local Docker Deployment"

echo -e "${CYAN}Configuration:${NC}"
echo -e "  Deploy Infrastructure: ${DEPLOY_INFRA}"
echo -e "  Deploy Databases:      ${DEPLOY_DBS}"
echo -e "  Deploy Services:       ${DEPLOY_SERVICES}"
echo -e "  Deploy Frontends:      ${DEPLOY_FRONTENDS}"
echo -e "  Skip Build:            ${SKIP_BUILD}"
echo -e "  Clean First:           ${CLEAN_FIRST}"
echo ""

# Check Docker
check_docker

# =============================================================================
# Clean up if requested
# =============================================================================
if [ "$CLEAN_FIRST" = true ]; then
    print_header "Cleaning up existing deployment"
    
    # Stop all xshopai containers
    print_step "Stopping all xshopai containers..."
    docker ps -a --filter "name=xshopai-" -q | xargs -r docker stop 2>/dev/null || true
    docker ps -a --filter "name=xshopai-" -q | xargs -r docker rm 2>/dev/null || true
    print_success "Containers removed"
    
    # Remove volumes
    print_step "Removing volumes..."
    docker volume ls --filter "name=xshopai_" -q | xargs -r docker volume rm 2>/dev/null || true
    print_success "Volumes removed"
    
    # Remove network
    cleanup_network
    
    print_success "Cleanup complete"
fi

# =============================================================================
# Deploy Network
# =============================================================================
print_progress "Setting up Docker Network"
source "$MODULES_DIR/01-network.sh"

# =============================================================================
# Deploy Infrastructure
# =============================================================================
if [ "$DEPLOY_INFRA" = true ]; then
    print_progress "Deploying Infrastructure Services"
    source "$MODULES_DIR/02-infrastructure.sh"
fi

# =============================================================================
# Deploy Databases
# =============================================================================
if [ "$DEPLOY_DBS" = true ]; then
    print_progress "Deploying MongoDB Databases"
    source "$MODULES_DIR/03-mongodb.sh"
    
    print_progress "Deploying PostgreSQL Databases"
    source "$MODULES_DIR/04-postgresql.sh"
    
    print_progress "Deploying SQL Server Databases"
    source "$MODULES_DIR/05-sqlserver.sh"
    
    print_progress "Deploying MySQL Database"
    source "$MODULES_DIR/06-mysql.sh"
fi

# =============================================================================
# Deploy Application Services
# =============================================================================
if [ "$DEPLOY_SERVICES" = true ]; then
    print_progress "Deploying Node.js Services"
    source "$MODULES_DIR/07-nodejs-services.sh"
    
    print_progress "Deploying Python Services"
    source "$MODULES_DIR/08-python-services.sh"
    
    print_progress "Deploying .NET Services"
    source "$MODULES_DIR/09-dotnet-services.sh"
    
    print_progress "Deploying Java Services"
    source "$MODULES_DIR/10-java-services.sh"
fi

# =============================================================================
# Deploy Frontend Applications
# =============================================================================
if [ "$DEPLOY_FRONTENDS" = true ]; then
    print_progress "Deploying Frontend Applications"
    source "$MODULES_DIR/11-frontends.sh"
fi

# =============================================================================
# Final Summary
# =============================================================================
TOTAL_TIME=$((SECONDS - SCRIPT_START_TIME))
print_header "Deployment Complete! (${TOTAL_TIME}s)"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                    xshopai Platform is Ready!                               ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n${CYAN}📱 Frontend Applications:${NC}"
echo -e "  Customer UI:            ${GREEN}http://localhost:3000${NC}"
echo -e "  Admin UI:               ${GREEN}http://localhost:3001${NC}"

echo -e "\n${CYAN}🔌 API Services:${NC}"
echo -e "  Web BFF:                ${GREEN}http://localhost:8014${NC}"
echo -e "  Auth Service:           ${GREEN}http://localhost:8004${NC}"
echo -e "  User Service:           ${GREEN}http://localhost:8002${NC}"
echo -e "  Product Service:        ${GREEN}http://localhost:8001${NC}"
echo -e "  Inventory Service:      ${GREEN}http://localhost:8005${NC}"
echo -e "  Order Service:          ${GREEN}http://localhost:8006${NC}"
echo -e "  Payment Service:        ${GREEN}http://localhost:8009${NC}"
echo -e "  Cart Service:           ${GREEN}http://localhost:8008${NC}"
echo -e "  Review Service:         ${GREEN}http://localhost:8010${NC}"
echo -e "  Admin Service:          ${GREEN}http://localhost:8003${NC}"
echo -e "  Order Processor:        ${GREEN}http://localhost:8007${NC}"
echo -e "  Notification Service:   ${GREEN}http://localhost:8011${NC}"
echo -e "  Audit Service:          ${GREEN}http://localhost:8012${NC}"
echo -e "  Chat Service:           ${GREEN}http://localhost:8013${NC}"

echo -e "\n${CYAN}🛠️ Infrastructure:${NC}"
echo -e "  RabbitMQ Management:    ${GREEN}http://localhost:15672${NC} (admin/admin123)"
echo -e "  Jaeger UI:              ${GREEN}http://localhost:16686${NC}"
echo -e "  Mailpit UI:             ${GREEN}http://localhost:8025${NC}"

echo -e "\n${CYAN}📊 Useful Commands:${NC}"
echo -e "  View all containers:    ${YELLOW}docker ps --filter 'name=xshopai-'${NC}"
echo -e "  View container logs:    ${YELLOW}docker logs -f xshopai-<service-name>${NC}"
echo -e "  Stop all containers:    ${YELLOW}./stop.sh${NC}"
echo -e "  Check status:           ${YELLOW}./status.sh${NC}"

print_success "Deployment completed successfully!"
