#!/bin/bash
# =============================================================================
# Auth Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None (stateless token issuer; user data is in user-service)
# Port: 8003
# =============================================================================

deploy_auth_service() {
    local service_name="auth-service"
    local runtime="NODE|18-lts"
    local port="8003"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local jwt_algorithm=$(load_secret "jwt-algorithm")
    local jwt_expires_in=$(load_secret "jwt-expires-in")
    local rabbitmq_url=$(load_secret "rabbitmq-url")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
        "JWT_SECRET=$jwt_secret"
        "JWT_ALGORITHM=$jwt_algorithm"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        "JWT_EXPIRES_IN=$jwt_expires_in"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
