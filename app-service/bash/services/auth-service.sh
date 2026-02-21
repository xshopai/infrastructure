#!/bin/bash
# =============================================================================
# Auth Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None (stateless token issuer; user data is in user-service)
# Port: 8080
# =============================================================================

deploy_auth_service() {
    local service_name="auth-service"
    local runtime="NODE|18-lts"
    local port="8080"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local jwt_algorithm=$(load_secret "jwt-algorithm")
    local jwt_expires_in=$(load_secret "jwt-expires-in")
    local rabbitmq_url=$(load_secret "rabbitmq-url")

    # User service URL for credential validation
    local user_service_url="https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"

    local settings=(
        "SERVICE_NAME=auth-service"
        "VERSION=1.0.0"
        "JWT_SECRET=$jwt_secret"
        "JWT_ALGORITHM=$jwt_algorithm"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        "JWT_EXPIRES_IN=$jwt_expires_in"
        "USER_SERVICE_URL=$user_service_url"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # OpenTelemetry
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=auth-service"
        # Logging
        "LOG_LEVEL=info"
        "LOG_FORMAT=json"
        "LOG_TO_CONSOLE=true"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}