#!/bin/bash
# =============================================================================
# Review Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB)
# Port: 8005
# =============================================================================

deploy_review_service() {
    local service_name="review-service"
    local runtime="NODE|18-lts"
    local port="8005"
    
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"
        "MONGODB_DB_NAME=review-service-db"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
