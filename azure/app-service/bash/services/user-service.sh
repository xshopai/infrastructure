#!/bin/bash
# =============================================================================
# User Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB)
# Port: 8002
# =============================================================================

deploy_user_service() {
    local service_name="user-service"
    local runtime="NODE|18-lts"
    local port="8002"
    
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"
        "MONGODB_DB_NAME=user-service-db"
        "JWT_SECRET=$JWT_SECRET"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
