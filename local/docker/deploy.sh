#!/bin/bash

# =============================================================================
# xshopai Local Docker Deployment Orchestrator
# =============================================================================
# Main entry point for deploying xshopai platform locally using Docker.
# Supports deploying everything or individual services.
#
# Architecture:
#   - Modular design: Each service has its own deployment script
#   - Individual deployment: Run any single service for debugging
#   - Pre-built images: Assumes Docker images are already built
#   - Optional Dapr: Supports running with or without Dapr sidecars
#
# Usage:
#   ./deploy.sh [options] [services...]
#
# Options:
#   --all                Deploy everything (default if no services specified)
#   --infra              Deploy infrastructure only (RabbitMQ, Redis, etc.)
#   --databases          Deploy databases only
#   --services           Deploy all application services
#   --frontends          Deploy frontend applications only
#   --build              Build Docker images before deploying
#   --dapr               Enable Dapr sidecars for services
#   --clean              Remove all containers and volumes before deploying
#   --help               Show this help message
#
# Individual Services (can combine multiple):
#   --auth-service       Deploy Auth Service
#   --user-service       Deploy User Service
#   --product-service    Deploy Product Service
#   --inventory-service  Deploy Inventory Service
#   --order-service      Deploy Order Service
#   --payment-service    Deploy Payment Service
#   --cart-service       Deploy Cart Service
#   --review-service     Deploy Review Service
#   --admin-service      Deploy Admin Service
#   --notification-service  Deploy Notification Service
#   --audit-service      Deploy Audit Service
#   --chat-service       Deploy Chat Service
#   --order-processor-service  Deploy Order Processor Service
#   --web-bff            Deploy Web BFF
#   --customer-ui        Deploy Customer UI
#   --admin-ui           Deploy Admin UI
#
# Examples:
#   ./deploy.sh                           # Deploy everything
#   ./deploy.sh --infra --databases       # Deploy only infra and databases
#   ./deploy.sh --auth-service            # Deploy only auth-service
#   ./deploy.sh --auth-service --user-service  # Deploy multiple services
#   ./deploy.sh --build --product-service # Build and deploy product-service
#   ./deploy.sh --dapr --all              # Deploy all with Dapr sidecars
#   ./deploy.sh --clean --all             # Clean and redeploy everything
# =============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
SERVICES_DIR="$MODULES_DIR/services"

# Source common utilities
source "$MODULES_DIR/common.sh"

# -----------------------------------------------------------------------------
# Default configuration
# -----------------------------------------------------------------------------
DEPLOY_ALL=false
DEPLOY_INFRA=false
DEPLOY_DBS=false
DEPLOY_SERVICES=false
DEPLOY_FRONTENDS=false
BUILD_IMAGES=false
DAPR_ENABLED=false
CLEAN_FIRST=false

# Individual service flags
declare -A SERVICES_TO_DEPLOY

# All available services
ALL_SERVICES=(
    "auth-service"
    "user-service"
    "product-service"
    "inventory-service"
    "order-service"
    "payment-service"
    "cart-service"
    "review-service"
    "admin-service"
    "notification-service"
    "audit-service"
    "chat-service"
    "order-processor-service"
    "web-bff"
    "customer-ui"
    "admin-ui"
)

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            DEPLOY_ALL=true
            shift
            ;;
        --infra)
            DEPLOY_INFRA=true
            shift
            ;;
        --databases)
            DEPLOY_DBS=true
            shift
            ;;
        --services)
            DEPLOY_SERVICES=true
            shift
            ;;
        --frontends)
            DEPLOY_FRONTENDS=true
            shift
            ;;
        --build)
            BUILD_IMAGES=true
            export BUILD_IMAGES=true
            shift
            ;;
        --dapr)
            DAPR_ENABLED=true
            export DAPR_ENABLED=true
            shift
            ;;
        --clean)
            CLEAN_FIRST=true
            shift
            ;;
        --help|-h)
            head -60 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        --auth-service|--user-service|--product-service|--inventory-service|\
        --order-service|--payment-service|--cart-service|--review-service|\
        --admin-service|--notification-service|--audit-service|--chat-service|\
        --order-processor-service|--web-bff|--customer-ui|--admin-ui)
            service_name="${1#--}"  # Remove -- prefix
            SERVICES_TO_DEPLOY[$service_name]=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no specific options given, deploy all
if [ "$DEPLOY_ALL" = false ] && [ "$DEPLOY_INFRA" = false ] && \
   [ "$DEPLOY_DBS" = false ] && [ "$DEPLOY_SERVICES" = false ] && \
   [ "$DEPLOY_FRONTENDS" = false ] && [ ${#SERVICES_TO_DEPLOY[@]} -eq 0 ]; then
    DEPLOY_ALL=true
fi

# If deploy all, enable everything
if [ "$DEPLOY_ALL" = true ]; then
    DEPLOY_INFRA=true
    DEPLOY_DBS=true
    DEPLOY_SERVICES=true
    DEPLOY_FRONTENDS=true
fi

# If deploy services flag is set, add all backend services
if [ "$DEPLOY_SERVICES" = true ]; then
    for service in "auth-service" "user-service" "product-service" "inventory-service" \
                   "order-service" "payment-service" "cart-service" "review-service" \
                   "admin-service" "notification-service" "audit-service" "chat-service" \
                   "order-processor-service" "web-bff"; do
        SERVICES_TO_DEPLOY[$service]=true
    done
fi

# If deploy frontends flag is set, add frontend services
if [ "$DEPLOY_FRONTENDS" = true ]; then
    SERVICES_TO_DEPLOY["customer-ui"]=true
    SERVICES_TO_DEPLOY["admin-ui"]=true
fi

# Track deployment progress
SCRIPT_START_TIME=$SECONDS

# -----------------------------------------------------------------------------
# Show deployment plan
# -----------------------------------------------------------------------------
print_header "xshopai Local Docker Deployment"

echo -e "${CYAN}Configuration:${NC}"
echo -e "  Build Images:     ${BUILD_IMAGES}"
echo -e "  Dapr Enabled:     ${DAPR_ENABLED}"
echo -e "  Clean First:      ${CLEAN_FIRST}"
echo -e "  Deploy Infra:     ${DEPLOY_INFRA}"
echo -e "  Deploy Databases: ${DEPLOY_DBS}"
echo ""

if [ ${#SERVICES_TO_DEPLOY[@]} -gt 0 ]; then
    echo -e "${CYAN}Services to deploy:${NC}"
    for service in "${!SERVICES_TO_DEPLOY[@]}"; do
        echo -e "  - $service"
    done
    echo ""
fi

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
print_header "Setting up Docker Network"
source "$MODULES_DIR/01-network.sh"

# =============================================================================
# Deploy Infrastructure
# =============================================================================
if [ "$DEPLOY_INFRA" = true ]; then
    print_header "Deploying Infrastructure Services"
    source "$MODULES_DIR/02-infrastructure.sh"
fi

# =============================================================================
# Deploy Databases
# =============================================================================
if [ "$DEPLOY_DBS" = true ]; then
    print_header "Deploying Databases"
    source "$MODULES_DIR/03-mongodb.sh"
    source "$MODULES_DIR/04-postgresql.sh"
    source "$MODULES_DIR/05-sqlserver.sh"
    source "$MODULES_DIR/06-mysql.sh"
fi

# =============================================================================
# Deploy Individual Services
# =============================================================================
if [ ${#SERVICES_TO_DEPLOY[@]} -gt 0 ]; then
    print_header "Deploying Application Services"
    
    for service in "${!SERVICES_TO_DEPLOY[@]}"; do
        service_script="$SERVICES_DIR/${service}.sh"
        
        if [ -f "$service_script" ]; then
            print_subheader "Deploying $service"
            source "$service_script"
        else
            print_error "Service script not found: $service_script"
        fi
    done
fi

# =============================================================================
# Final Summary
# =============================================================================
TOTAL_TIME=$((SECONDS - SCRIPT_START_TIME))
print_header "Deployment Complete! (${TOTAL_TIME}s)"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                    xshopai Platform is Ready!                               ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Show running containers
echo -e "\n${CYAN}Running xshopai containers:${NC}"
docker ps --filter "name=xshopai-" --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  No containers running"

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

if [ "$DAPR_ENABLED" = true ]; then
    echo -e "\n${CYAN}🔗 Dapr Sidecars:${NC}"
    echo -e "  Dapr sidecars are running alongside services"
    echo -e "  Each service can communicate via Dapr at localhost:3500"
fi

echo -e "\n${CYAN}📊 Useful Commands:${NC}"
echo -e "  View all containers:    ${YELLOW}docker ps --filter 'name=xshopai-'${NC}"
echo -e "  View container logs:    ${YELLOW}docker logs -f xshopai-<service-name>${NC}"
echo -e "  Deploy single service:  ${YELLOW}./deploy.sh --<service-name>${NC}"
echo -e "  Stop all containers:    ${YELLOW}./stop.sh${NC}"
echo -e "  Check status:           ${YELLOW}./status.sh${NC}"

print_success "Deployment completed successfully!"
