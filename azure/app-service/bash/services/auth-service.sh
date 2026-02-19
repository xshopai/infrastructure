#!/bin/bash
# =============================================================================
# Auth Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB)
# Port: 8003
# =============================================================================

deploy_auth_service() {
    local service_name="auth-service"
    local runtime="NODE|18-lts"
    local port="8003"
    
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"
        "MONGODB_DB_NAME=auth-service-db"
        "JWT_SECRET=$JWT_SECRET"
        "JWT_EXPIRES_IN=7d"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
