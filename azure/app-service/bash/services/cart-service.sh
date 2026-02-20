#!/bin/bash
# =============================================================================
# Cart Service Deployment
# =============================================================================
# Runtime: Java 17 (Quarkus - NOT Spring Boot)
# Database: Redis (Azure Cache for Redis) via Quarkus Redis extension
# Port: 8008
# Quarkus reads REDIS_HOST/PORT/PASSWORD and RABBITMQ_HOST/PORT/USERNAME/PASSWORD
# from environment and applies them to quarkus.redis.hosts and rabbitmq.* properties
# =============================================================================

deploy_cart_service() {
    local service_name="cart-service"
    local runtime="JAVA|17-java17"
    local port="8008"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local rabbitmq_user=$(load_secret "rabbitmq-user")
    local rabbitmq_password=$(load_secret "rabbitmq-password")
    # cart-service token (sent as SERVICE_TOKEN to authenticate outbound calls)
    local service_token=$(load_secret "cart-service-token")
    # Parse RabbitMQ host: amqp://user:pass@HOST:5672/
    local rabbitmq_host=$(echo "$rabbitmq_url" | sed 's|amqp://[^@]*@\([^:]*\):.*|\1|')

    local settings=(
        # Quarkus HTTP port (overrides quarkus.http.port in application.properties)
        "QUARKUS_HTTP_PORT=$port"
        # Redis: Override quarkus.redis.hosts directly to use rediss:// (SSL) for Azure Cache for Redis on port 6380
        "QUARKUS_REDIS_HOSTS=rediss://:${REDIS_KEY}@${REDIS_HOST}:6380"
        "REDIS_HOST=$REDIS_HOST"
        "REDIS_PORT=6380"
        "REDIS_PASSWORD=$REDIS_KEY"
        # RabbitMQ: Quarkus reads via rabbitmq.host=${RABBITMQ_HOST} etc.
        "RABBITMQ_HOST=$rabbitmq_host"
        "RABBITMQ_PORT=5672"
        "RABBITMQ_USERNAME=$rabbitmq_user"
        "RABBITMQ_PASSWORD=$rabbitmq_password"
        "RABBITMQ_EXCHANGE=xshopai.events"
        # JWT: smallrye.jwt.verify.key=${JWT_SECRET}
        "JWT_SECRET=$jwt_secret"
        # Service-to-service auth token this service sends on outbound calls
        "SERVICE_TOKEN=$service_token"
        "SERVICE_TOKEN_ENABLED=true"
        # Downstream service URLs
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        # OpenTelemetry
        "OTEL_SERVICE_NAME=cart-service"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}