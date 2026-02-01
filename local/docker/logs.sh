#!/bin/bash

# =============================================================================
# xshopai Local Docker Logs Script
# =============================================================================
# View logs for xshopai Docker containers
#
# Usage:
#   ./logs.sh <service-name> [options]
#   ./logs.sh --all
#
# Examples:
#   ./logs.sh auth-service           # View auth-service logs
#   ./logs.sh product-service -f     # Follow product-service logs
#   ./logs.sh --all                  # View all container logs
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

# Parse arguments
SERVICE_NAME=""
FOLLOW=false
TAIL_LINES=100
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all|-a)
            SHOW_ALL=true
            shift
            ;;
        -f|--follow)
            FOLLOW=true
            shift
            ;;
        -n|--tail)
            TAIL_LINES="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./logs.sh <service-name> [options]"
            echo ""
            echo "Options:"
            echo "  -f, --follow    Follow log output"
            echo "  -n, --tail N    Number of lines to show (default: 100)"
            echo "  -a, --all       Show logs from all containers"
            echo ""
            echo "Available services:"
            echo "  auth-service, user-service, admin-service, product-service"
            echo "  inventory-service, order-service, payment-service, cart-service"
            echo "  review-service, notification-service, audit-service, chat-service"
            echo "  web-bff, order-processor-service, customer-ui, admin-ui"
            echo ""
            echo "Infrastructure:"
            echo "  rabbitmq, redis, jaeger, mailpit"
            echo ""
            echo "Databases:"
            echo "  auth-mongodb, user-mongodb, product-mongodb, review-mongodb"
            echo "  audit-postgres, order-processor-postgres"
            echo "  payment-sqlserver, order-sqlserver"
            echo "  inventory-mysql"
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            exit 1
            ;;
        *)
            SERVICE_NAME="$1"
            shift
            ;;
    esac
done

# Show all logs
if [ "$SHOW_ALL" = true ]; then
    print_header "All Container Logs"
    
    CONTAINERS=$(docker ps --filter "name=xshopai-" --format "{{.Names}}")
    
    if [ -z "$CONTAINERS" ]; then
        print_error "No running xshopai containers found"
        exit 1
    fi
    
    for container in $CONTAINERS; do
        echo -e "\n${CYAN}━━━ $container ━━━${NC}"
        docker logs --tail 20 "$container" 2>&1 || true
    done
    
    exit 0
fi

# Validate service name
if [ -z "$SERVICE_NAME" ]; then
    print_error "Service name required. Use --help for usage."
    exit 1
fi

# Construct container name
CONTAINER_NAME="xshopai-${SERVICE_NAME}"

# Check if container exists
if ! container_exists "$CONTAINER_NAME"; then
    print_error "Container not found: $CONTAINER_NAME"
    echo ""
    echo "Available containers:"
    docker ps -a --filter "name=xshopai-" --format "  {{.Names}}" | sed 's/xshopai-/  /'
    exit 1
fi

# Build log command
LOG_CMD="docker logs"
LOG_CMD="$LOG_CMD --tail $TAIL_LINES"

if [ "$FOLLOW" = true ]; then
    LOG_CMD="$LOG_CMD -f"
fi

LOG_CMD="$LOG_CMD $CONTAINER_NAME"

print_header "Logs: $SERVICE_NAME"
echo -e "${CYAN}Container: $CONTAINER_NAME${NC}"
echo -e "${CYAN}Lines: $TAIL_LINES${NC}"
echo ""

# Execute log command
exec $LOG_CMD
