#!/bin/bash
# =============================================================================
# Web BFF (Backend for Frontend) Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None (API gateway / orchestration layer)
# Port: 8080
# =============================================================================

deploy_web_bff() {
    local service_name="web-bff"
    local runtime="NODE|20-lts"
    local port="8080"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")

    local settings=(
        "SERVICE_NAME=web-bff"
        "VERSION=1.0.0"
        "JWT_SECRET=$jwt_secret"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        "MESSAGING_PROVIDER=rabbitmq"
        "ALLOWED_ORIGINS=https://app-customer-ui-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        # Downstream service URLs
        "AUTH_SERVICE_URL=https://app-auth-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "CART_SERVICE_URL=https://app-cart-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PAYMENT_SERVICE_URL=https://app-payment-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "REVIEW_SERVICE_URL=https://app-review-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ADMIN_SERVICE_URL=https://app-admin-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "CHAT_SERVICE_URL=https://app-chat-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        # OpenTelemetry (Azure Application Insights)
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=web-bff"
        # Logging
        "LOG_LEVEL=info"
        "LOG_FORMAT=json"
        "LOG_TO_CONSOLE=true"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}