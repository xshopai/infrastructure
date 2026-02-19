#!/bin/bash
# =============================================================================
# Inventory Service Deployment
# =============================================================================
# Runtime: Python 3.11
# Database: PostgreSQL
# Port: 8004
# =============================================================================

deploy_inventory_service() {
    local service_name="inventory-service"
    local runtime="PYTHON|3.11"
    local port="8004"
    
    local settings=(
        "DATABASE_URL=$POSTGRESQL_CONNECTION"
        "POSTGRESQL_HOST=$POSTGRESQL_HOST"
        "POSTGRESQL_USER=$DB_ADMIN_USER"
        "POSTGRESQL_PASSWORD=$DB_ADMIN_PASSWORD"
        "POSTGRESQL_DB=inventory-service-db"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
