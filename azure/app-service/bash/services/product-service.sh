#!/bin/bash
# =============================================================================
# Product Service Deployment
# =============================================================================
# Runtime: Python 3.11
# Database: MongoDB (Cosmos DB)
# Port: 8001
# =============================================================================

deploy_product_service() {
    local service_name="product-service"
    local runtime="PYTHON|3.11"
    local port="8001"
    
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"
        "MONGODB_DB_NAME=product-service-db"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
