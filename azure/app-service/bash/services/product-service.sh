#!/bin/bash
# =============================================================================
# Product Service Deployment
# =============================================================================
# Runtime: Python 3.11 (FastAPI)
# Database: MongoDB (Cosmos DB) - product-service database
# Port: 8001
# =============================================================================

deploy_product_service() {
    local service_name="product-service"
    local runtime="PYTHON|3.11"
    local port="8001"

    # Load secrets from Key Vault
    local mongodb_uri=$(load_secret "product-service-mongodb-uri")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local jwt_algorithm=$(load_secret "jwt-algorithm")
    local service_product_token=$(load_secret "admin-service-token")
    local service_order_token=$(load_secret "order-service-token")
    local service_cart_token=$(load_secret "cart-service-token")
    local service_webbff_token=$(load_secret "web-bff-token")

    local settings=(
        # Service Info
        "NAME=product-service"
        "API_VERSION=1.0.0"
        # Database
        "MONGODB_URI=$mongodb_uri"
        "MONGODB_DB_NAME=product_service_db"
        # Messaging
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # JWT Authentication
        "JWT_SECRET=$jwt_secret"
        "JWT_ALGORITHM=$jwt_algorithm"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        # Service-to-Service Tokens
        "SERVICE_PRODUCT_TOKEN=$service_product_token"
        "SERVICE_ORDER_TOKEN=$service_order_token"
        "SERVICE_CART_TOKEN=$service_cart_token"
        "SERVICE_WEBBFF_TOKEN=$service_webbff_token"
        # OpenTelemetry (Azure Application Insights)
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=product-service"
        # Logging
        "LOG_LEVEL=INFO"
        "LOG_FORMAT=json"
        "LOG_TO_CONSOLE=true"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}