#!/bin/bash
# =============================================================================
# Order Service Deployment
# =============================================================================
# Runtime: .NET 8.0
# Database: SQL Server
# Port: 8006
# =============================================================================

deploy_order_service() {
    local service_name="order-service"
    local runtime="DOTNETCORE|8.0"
    local port="8006"
    
    local settings=(
        "ConnectionStrings__DefaultConnection=$SQL_ORDER_CONNECTION"
        "ASPNETCORE_ENVIRONMENT=${ENVIRONMENT^}"
        "Redis__Host=$REDIS_HOST"
        "Redis__Key=$REDIS_KEY"
        "RabbitMQ__Host=$RABBITMQ_HOST"
        "RabbitMQ__User=$RABBITMQ_USER"
        "RabbitMQ__Password=$RABBITMQ_PASSWORD"
        "Services__CartService=https://app-cart-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "Services__ProductService=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "Services__InventoryService=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
