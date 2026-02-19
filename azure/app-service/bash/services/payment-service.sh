#!/bin/bash
# =============================================================================
# Payment Service Deployment
# =============================================================================
# Runtime: .NET 8.0
# Database: SQL Server
# Port: 8009
# =============================================================================

deploy_payment_service() {
    local service_name="payment-service"
    local runtime="DOTNETCORE|8.0"
    local port="8009"
    
    local settings=(
        "ConnectionStrings__DefaultConnection=$SQL_PAYMENT_CONNECTION"
        "ASPNETCORE_ENVIRONMENT=${ENVIRONMENT^}"
        "Redis__Host=$REDIS_HOST"
        "Redis__Key=$REDIS_KEY"
        "RabbitMQ__Host=$RABBITMQ_HOST"
        "RabbitMQ__User=$RABBITMQ_USER"
        "RabbitMQ__Password=$RABBITMQ_PASSWORD"
        "Stripe__SecretKey=${STRIPE_SECRET_KEY:-}"
        "Stripe__WebhookSecret=${STRIPE_WEBHOOK_SECRET:-}"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
