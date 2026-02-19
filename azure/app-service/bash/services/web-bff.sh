#!/bin/bash
# =============================================================================
# Web BFF (Backend for Frontend) Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None (API gateway / orchestration layer)
# Port: 8014
# =============================================================================

deploy_web_bff() {
    local service_name="web-bff"
    local runtime="NODE|18-lts"
    local port="8014"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
        "JWT_SECRET=$jwt_secret"
        "JWT_ISSUER=$jwt_issuer"
        "MESSAGING_PROVIDER=rabbitmq"
        "ALLOWED_ORIGINS=https://app-customer-ui-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "AUTH_SERVICE_URL=https://app-auth-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "CART_SERVICE_URL=https://app-cart-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PAYMENT_SERVICE_URL=https://app-payment-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "REVIEW_SERVICE_URL=https://app-review-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ADMIN_SERVICE_URL=https://app-admin-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"

    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}