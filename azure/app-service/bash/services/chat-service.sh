#!/bin/bash
# =============================================================================
# Chat Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MySQL
# Port: 8013
# =============================================================================

deploy_chat_service() {
    local service_name="chat-service"
    local runtime="NODE|18-lts"
    local port="8013"
    
    local settings=(
        "MYSQL_HOST=$MYSQL_HOST"
        "MYSQL_USER=$DB_ADMIN_USER"
        "MYSQL_PASSWORD=$DB_ADMIN_PASSWORD"
        "MYSQL_DATABASE=chat-service-db"
        "DATABASE_URL=$MYSQL_CHAT_CONNECTION"
        "JWT_SECRET=$JWT_SECRET"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
