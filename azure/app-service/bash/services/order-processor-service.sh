#!/bin/bash
# =============================================================================
# Order Processor Service Deployment
# =============================================================================
# Runtime: Java 17
# Database: SQL Server
# Port: 8008
# =============================================================================

deploy_order_processor_service() {
    local service_name="order-processor-service"
    local runtime="JAVA|17-java17"
    local port="8008"
    
    local settings=(
        "SPRING_DATASOURCE_URL=jdbc:sqlserver://${SQL_HOST}:1433;database=OrderDB;encrypt=true;trustServerCertificate=false"
        "SPRING_DATASOURCE_USERNAME=$DB_ADMIN_USER"
        "SPRING_DATASOURCE_PASSWORD=$DB_ADMIN_PASSWORD"
        "SPRING_PROFILES_ACTIVE=$ENVIRONMENT"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_KEY=$REDIS_KEY"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PAYMENT_SERVICE_URL=https://app-payment-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
