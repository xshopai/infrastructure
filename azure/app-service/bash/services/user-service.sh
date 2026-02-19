#!/bin/bash
# =============================================================================
# User Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB) - user-service database
# Port: 8002
# =============================================================================

deploy_user_service() {
    local service_name="user-service"
    local runtime="NODE|18-lts"
    local port="8002"

    # Load secrets from Key Vault
    local mongodb_uri=$(load_secret "user-service-mongodb-uri")
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local jwt_algorithm=$(load_secret "jwt-algorithm")
    local jwt_expires_in=$(load_secret "jwt-expires-in")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    # Service-to-service tokens (used to verify inbound calls from other services)
    local token_auth=$(load_secret "auth-service-token")
    local token_admin=$(load_secret "admin-service-token")
    local token_order=$(load_secret "order-service-token")
    local token_webbff=$(load_secret "web-bff-token")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
        "MONGODB_URI=$mongodb_uri"
        "MONGODB_DB_NAME=user_service_db"
        "JWT_SECRET=$jwt_secret"
        "JWT_ALGORITHM=$jwt_algorithm"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        "JWT_EXPIRES_IN=$jwt_expires_in"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        "SERVICE_AUTH_TOKEN=$token_auth"
        "SERVICE_ADMIN_TOKEN=$token_admin"
        "SERVICE_ORDER_TOKEN=$token_order"
        "SERVICE_WEBBFF_TOKEN=$token_webbff"

    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}