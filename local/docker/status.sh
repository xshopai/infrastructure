#!/bin/bash

# =============================================================================
# xshopai Local Docker Status Script
# =============================================================================
# Shows the status of all xshopai Docker containers
#
# Usage:
#   ./status.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

print_header "xshopai Container Status"

# Function to print container status with health
print_container_status() {
    local container_name="$1"
    local display_name="$2"
    local port="$3"
    
    if is_container_running "$container_name"; then
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "N/A")
        local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
        
        if [ "$health" = "healthy" ]; then
            echo -e "  ${GREEN}●${NC} $display_name (port $port) - ${GREEN}healthy${NC}"
        elif [ "$health" = "unhealthy" ]; then
            echo -e "  ${RED}●${NC} $display_name (port $port) - ${RED}unhealthy${NC}"
        elif [ "$status" = "running" ]; then
            echo -e "  ${YELLOW}●${NC} $display_name (port $port) - ${YELLOW}running${NC}"
        fi
    else
        echo -e "  ${RED}○${NC} $display_name (port $port) - ${RED}stopped${NC}"
    fi
}

# =============================================================================
# Infrastructure
# =============================================================================
print_subheader "Infrastructure Services"
print_container_status "xshopai-rabbitmq" "RabbitMQ" "5672/15672"
print_container_status "xshopai-redis" "Redis" "6379"
print_container_status "xshopai-jaeger" "Jaeger" "16686"
print_container_status "xshopai-mailpit" "Mailpit" "1025/8025"

# =============================================================================
# MongoDB Databases
# =============================================================================
print_subheader "MongoDB Databases"
print_container_status "xshopai-auth-mongodb" "Auth MongoDB" "27017"
print_container_status "xshopai-user-mongodb" "User MongoDB" "27018"
print_container_status "xshopai-product-mongodb" "Product MongoDB" "27019"
print_container_status "xshopai-review-mongodb" "Review MongoDB" "27020"

# =============================================================================
# PostgreSQL Databases
# =============================================================================
print_subheader "PostgreSQL Databases"
print_container_status "xshopai-audit-postgres" "Audit PostgreSQL" "5434"
print_container_status "xshopai-order-processor-postgres" "Order Processor PostgreSQL" "5435"

# =============================================================================
# SQL Server Databases
# =============================================================================
print_subheader "SQL Server Databases"
print_container_status "xshopai-payment-sqlserver" "Payment SQL Server" "1433"
print_container_status "xshopai-order-sqlserver" "Order SQL Server" "1434"

# =============================================================================
# MySQL Database
# =============================================================================
print_subheader "MySQL Database"
print_container_status "xshopai-inventory-mysql" "Inventory MySQL" "3306"

# =============================================================================
# Node.js Services
# =============================================================================
print_subheader "Node.js Services"
print_container_status "xshopai-auth-service" "Auth Service" "8004"
print_container_status "xshopai-user-service" "User Service" "8002"
print_container_status "xshopai-admin-service" "Admin Service" "8003"
print_container_status "xshopai-review-service" "Review Service" "8010"
print_container_status "xshopai-audit-service" "Audit Service" "8012"
print_container_status "xshopai-notification-service" "Notification Service" "8011"
print_container_status "xshopai-chat-service" "Chat Service" "8013"
print_container_status "xshopai-web-bff" "Web BFF" "8014"

# =============================================================================
# Python Services
# =============================================================================
print_subheader "Python Services"
print_container_status "xshopai-product-service" "Product Service" "8001"
print_container_status "xshopai-inventory-service" "Inventory Service" "8005"

# =============================================================================
# .NET Services
# =============================================================================
print_subheader ".NET Services"
print_container_status "xshopai-order-service" "Order Service" "8006"
print_container_status "xshopai-payment-service" "Payment Service" "8009"

# =============================================================================
# Java Services
# =============================================================================
print_subheader "Java Services"
print_container_status "xshopai-cart-service" "Cart Service" "8008"
print_container_status "xshopai-order-processor-service" "Order Processor" "8007"

# =============================================================================
# Frontend Applications
# =============================================================================
print_subheader "Frontend Applications"
print_container_status "xshopai-customer-ui" "Customer UI" "3000"
print_container_status "xshopai-admin-ui" "Admin UI" "3001"

# =============================================================================
# Summary
# =============================================================================
echo ""
RUNNING_COUNT=$(docker ps --filter "name=xshopai-" -q | wc -l)
TOTAL_COUNT=$(docker ps -a --filter "name=xshopai-" -q | wc -l)

echo -e "${CYAN}Summary:${NC} $RUNNING_COUNT of $TOTAL_COUNT containers running"
echo ""

# Show resource usage
echo -e "${CYAN}Resource Usage:${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps --filter "name=xshopai-" -q) 2>/dev/null || echo "  No containers running"
