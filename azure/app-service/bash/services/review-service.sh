#!/bin/bash
# =============================================================================
# Review Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB) - review-service database
# Port: 8005
# =============================================================================

deploy_review_service() {
    local service_name="review-service"
    local runtime="NODE|18-lts"
    local port="8005"

    # Load secrets from Key Vault
    local mongodb_uri=$(load_secret "review-service-mongodb-uri")
    local jwt_secret=$(load_secret "jwt-secret")
    local rabbitmq_url=$(load_secret "rabbitmq-url")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
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

    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}