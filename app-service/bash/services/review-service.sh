#!/bin/bash
# =============================================================================
# Review Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB) - review-service database
# Port: 8080
# =============================================================================

deploy_review_service() {
    local service_name="review-service"
    local runtime="NODE|18-lts"
    local port="8080"

    # Load secrets from Key Vault
    local mongodb_uri=$(load_secret "review-service-mongodb-uri")
    local jwt_secret=$(load_secret "jwt-secret")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    # Service-to-service tokens (used to verify inbound calls from other services)
    local token_product=$(load_secret "product-service-token")
    local token_order=$(load_secret "order-service-token")
    local token_webbff=$(load_secret "web-bff-token")

    local settings=(
        "SERVICE_NAME=review-service"
        "VERSION=1.0.0"
        "MONGODB_URI=$mongodb_uri"
        "MONGODB_DB_NAME=review_service_db"
        "JWT_SECRET=$jwt_secret"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        "CORS_ORIGIN=https://app-customer-ui-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        # Service-to-Service Tokens
        "SERVICE_PRODUCT_TOKEN=$token_product"
        "SERVICE_ORDER_TOKEN=$token_order"
        "SERVICE_WEBBFF_TOKEN=$token_webbff"
        # OpenTelemetry (Azure Application Insights)
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=review-service"
        # Logging
        "LOG_LEVEL=info"
        "LOG_FORMAT=json"
        "LOG_TO_CONSOLE=true"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}