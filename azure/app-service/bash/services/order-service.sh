#!/bin/bash
# =============================================================================
# Order Service Deployment
# =============================================================================
# Runtime: .NET 8.0
# Database: SQL Server (Azure SQL)
# Port: 8006
# Code reads DATABASE_CONNECTION_STRING (not ConnectionStrings:DefaultConnection)
# RabbitMQ uses RABBITMQ_CONNECTION_STRING (full amqp:// URL)
# =============================================================================

deploy_order_service() {
    local service_name="order-service"
    local runtime="DOTNETCORE|8.0"
    local port="8006"

    # Load secrets from Key Vault
    local sql_connection=$(load_secret "order-service-sql-connection")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local jwt_secret=$(load_secret "jwt-secret")

    local settings=(
        "ASPNETCORE_ENVIRONMENT=${ENVIRONMENT^}"
        "ASPNETCORE_URLS=http://0.0.0.0:$port"
        # Database (ConfigurationService reads DATABASE_CONNECTION_STRING directly)
        "DATABASE_CONNECTION_STRING=$sql_connection"
        # RabbitMQ (MessagingProviderFactory reads RABBITMQ_CONNECTION_STRING as full amqp:// URL)
        "RABBITMQ_CONNECTION_STRING=$rabbitmq_url"
        "RabbitMQ__ExchangeName=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # JWT
        "JWT_SECRET=$jwt_secret"
        # Telemetry (App Insights via OTEL)
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=order-service"
        # Downstream service URLs (Services:CartService -> Services__CartService in env vars)
        "Services__CartService=https://app-cart-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "Services__ProductService=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "Services__InventoryService=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "Services__UserService=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"

    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}