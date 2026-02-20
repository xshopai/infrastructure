#!/bin/bash
# =============================================================================
# Payment Service Deployment
# =============================================================================
# Runtime: .NET 8.0
# Database: SQL Server (Azure SQL)
# Port: 8009
# Code reads ConnectionStrings:DefaultConnection and Jwt:Key (double-underscore for env)
# RabbitMQ uses RABBITMQ_CONNECTION_STRING (full amqp:// URL)
# =============================================================================

deploy_payment_service() {
    local service_name="payment-service"
    local runtime="DOTNETCORE|8.0"
    local port="8009"

    # Load secrets from Key Vault
    local sql_connection=$(load_secret "payment-service-sql-connection")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local jwt_key=$(load_secret "jwt-secret")
    # Service tokens for validating inbound calls
    local token_order=$(load_secret "order-service-token")
    local token_user=$(load_secret "user-service-token")

    local settings=(
        "ASPNETCORE_ENVIRONMENT=${ENVIRONMENT^}"
        "ASPNETCORE_URLS=http://0.0.0.0:$port"
        # Database (GetConnectionString("DefaultConnection"))
        "ConnectionStrings__DefaultConnection=$sql_connection"
        # RabbitMQ (RABBITMQ_CONNECTION_STRING = full amqp:// URL)
        "RABBITMQ_CONNECTION_STRING=$rabbitmq_url"
        "RabbitMQ__ExchangeName=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # JWT: Jwt:Key -> Jwt__Key in env var
        "Jwt__Key=$jwt_key"
        "Jwt__Issuer=auth-service"
        "Jwt__Audience=xshopai-platform"
        # Service tokens used to verify inbound requests
        "ServiceTokens__OrderService=$token_order"
        "ServiceTokens__UserService=$token_user"
        # Telemetry (App Insights via OTEL)
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=payment-service"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}