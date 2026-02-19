#!/bin/bash
# =============================================================================
# Admin Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None (aggregates data from other services via HTTP)
# Port: 8012
# =============================================================================

deploy_admin_service() {
    local service_name="admin-service"
    local runtime="NODE|18-lts"
    local port="8012"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    # admin-service sends its own token when calling user-service
    local service_user_token=$(load_secret "admin-service-token")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
        "JWT_SECRET=$jwt_secret"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        "SERVICE_USER_TOKEN=$service_user_token"
        "AUTH_SERVICE_URL=https://app-auth-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "PAYMENT_SERVICE_URL=https://app-payment-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "AUDIT_SERVICE_URL=https://app-audit-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "NOTIFICATION_SERVICE_URL=https://app-notification-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
