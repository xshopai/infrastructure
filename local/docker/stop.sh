#!/bin/bash

# =============================================================================
# xshopai Local Docker Stop Script
# =============================================================================
# Stops all xshopai Docker containers
#
# Usage:
#   ./stop.sh [options]
#
# Options:
#   --all         Stop all containers (default)
#   --services    Stop only application services
#   --db          Stop only databases
#   --infra       Stop only infrastructure
#   --remove      Also remove containers after stopping
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

# Parse arguments
STOP_ALL=true
STOP_SERVICES=false
STOP_DB=false
STOP_INFRA=false
REMOVE_CONTAINERS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            STOP_ALL=true
            shift
            ;;
        --services)
            STOP_ALL=false
            STOP_SERVICES=true
            shift
            ;;
        --db)
            STOP_ALL=false
            STOP_DB=true
            shift
            ;;
        --infra)
            STOP_ALL=false
            STOP_INFRA=true
            shift
            ;;
        --remove)
            REMOVE_CONTAINERS=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "Stopping xshopai Containers"

# Define container groups
INFRA_CONTAINERS=(
    "xshopai-rabbitmq"
    "xshopai-redis"
    "xshopai-jaeger"
    "xshopai-mailpit"
)

DB_CONTAINERS=(
    "xshopai-auth-mongodb"
    "xshopai-user-mongodb"
    "xshopai-product-mongodb"
    "xshopai-review-mongodb"
    "xshopai-audit-postgres"
    "xshopai-order-processor-postgres"
    "xshopai-payment-sqlserver"
    "xshopai-order-sqlserver"
    "xshopai-inventory-mysql"
)

SERVICE_CONTAINERS=(
    "xshopai-auth-service"
    "xshopai-user-service"
    "xshopai-admin-service"
    "xshopai-product-service"
    "xshopai-inventory-service"
    "xshopai-order-service"
    "xshopai-payment-service"
    "xshopai-cart-service"
    "xshopai-order-processor-service"
    "xshopai-review-service"
    "xshopai-notification-service"
    "xshopai-audit-service"
    "xshopai-chat-service"
    "xshopai-web-bff"
    "xshopai-customer-ui"
    "xshopai-admin-ui"
)

stop_containers() {
    local containers=("$@")
    for container in "${containers[@]}"; do
        if is_container_running "$container"; then
            print_step "Stopping $container..."
            docker stop "$container" 2>/dev/null || true
            if [ "$REMOVE_CONTAINERS" = true ]; then
                docker rm "$container" 2>/dev/null || true
            fi
            print_success "Stopped $container"
        else
            print_info "$container is not running"
        fi
    done
}

# Stop appropriate containers
if [ "$STOP_ALL" = true ]; then
    print_subheader "Stopping Application Services"
    stop_containers "${SERVICE_CONTAINERS[@]}"
    
    print_subheader "Stopping Databases"
    stop_containers "${DB_CONTAINERS[@]}"
    
    print_subheader "Stopping Infrastructure"
    stop_containers "${INFRA_CONTAINERS[@]}"
else
    if [ "$STOP_SERVICES" = true ]; then
        print_subheader "Stopping Application Services"
        stop_containers "${SERVICE_CONTAINERS[@]}"
    fi
    
    if [ "$STOP_DB" = true ]; then
        print_subheader "Stopping Databases"
        stop_containers "${DB_CONTAINERS[@]}"
    fi
    
    if [ "$STOP_INFRA" = true ]; then
        print_subheader "Stopping Infrastructure"
        stop_containers "${INFRA_CONTAINERS[@]}"
    fi
fi

print_success "Stop operation complete"
