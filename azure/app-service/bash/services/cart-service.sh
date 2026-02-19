#!/bin/bash
# =============================================================================
# Cart Service Deployment
# =============================================================================
# Runtime: Java 17
# Database: MySQL
# Port: 8007
# =============================================================================

deploy_cart_service() {
    local service_name="cart-service"
    local runtime="JAVA|17-java17"
    local port="8007"
    
    local settings=(
        "SPRING_DATASOURCE_URL=jdbc:mysql://${MYSQL_HOST}:3306/cart-service-db?useSSL=true&requireSSL=true"
        "SPRING_DATASOURCE_USERNAME=$DB_ADMIN_USER"
        "SPRING_DATASOURCE_PASSWORD=$DB_ADMIN_PASSWORD"
        "SPRING_PROFILES_ACTIVE=$ENVIRONMENT"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
