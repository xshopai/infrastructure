#!/bin/bash
# =============================================================================
# Order Processor Service Deployment
# =============================================================================
# Runtime: Java 17 (Spring Boot)
# Database: PostgreSQL (Azure Flexible Server)
# Port: 8007
# Spring relaxed binding: RABBITMQ_HOST -> rabbitmq.host, SERVER_PORT -> server.port
# =============================================================================

deploy_order_processor_service() {
    local service_name="order-processor-service"
    local runtime="JAVA|17-java17"
    local port="8007"

    # Load secrets from Key Vault
    local pg_jdbc_url=$(load_secret "order-processor-service-postgres-url")
    local pg_user=$(load_secret "postgres-admin-user")
    local pg_password=$(load_secret "postgres-admin-password")
    local jwt_secret=$(load_secret "jwt-secret")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local rabbitmq_user=$(load_secret "rabbitmq-user")
    local rabbitmq_password=$(load_secret "rabbitmq-password")
    # Parse RabbitMQ host from URL
    local rabbitmq_host=$(echo "$rabbitmq_url" | sed 's|amqp://[^@]*@\([^:]*\):.*|\1|')

    local settings=(
        # Spring Boot port override
        "SERVER_PORT=$port"
        # PostgreSQL datasource
        "SPRING_DATASOURCE_URL=$pg_jdbc_url"
        "SPRING_DATASOURCE_USERNAME=$pg_user"
        "SPRING_DATASOURCE_PASSWORD=$pg_password"
        # RabbitMQ (Spring relaxed binding: RABBITMQ_HOST -> rabbitmq.host)
        "RABBITMQ_HOST=$rabbitmq_host"
        "RABBITMQ_PORT=5672"
        "RABBITMQ_USERNAME=$rabbitmq_user"
        "RABBITMQ_PASSWORD=$rabbitmq_password"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # JWT (bound directly via @Value("${JWT_SECRET:}"))
        "JWT_SECRET=$jwt_secret"
        # Downstream service URLs
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PAYMENT_SERVICE_URL=https://app-payment-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "NOTIFICATION_SERVICE_URL=https://app-notification-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
