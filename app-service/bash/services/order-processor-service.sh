#!/bin/bash
# =============================================================================
# Order Processor Service Deployment
# =============================================================================
# Runtime: Java 17 (Spring Boot)
# Database: PostgreSQL (Azure Flexible Server)
# Port: 8080
# Spring relaxed binding:
#   RABBITMQ_HOST        -> rabbitmq.host
#   SERVER_PORT          -> server.port
#   SPRING_DATASOURCE_*  -> spring.datasource.*
#   SERVICES_ORDER_URL   -> services.order.url  (DaprServiceClient)
# =============================================================================

deploy_order_processor_service() {
    local service_name="order-processor-service"
    local runtime="JAVA|17-java17"
    local port="8080"

    # Load secrets from Key Vault
    local pg_jdbc_url=$(load_secret "order-processor-service-postgres-url")
    local pg_user=$(load_secret "postgres-admin-user")
    local pg_password=$(load_secret "postgres-admin-password")
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local rabbitmq_user=$(load_secret "rabbitmq-user")
    local rabbitmq_password=$(load_secret "rabbitmq-password")
    # Parse RabbitMQ host from URL: amqp://user:pass@HOST:5672/
    local rabbitmq_host=$(echo "$rabbitmq_url" | sed 's|amqp://[^@]*@\([^:]*\):.*|\1|')

    # Downstream service base URLs
    local order_url="https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    local inventory_url="https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    local payment_url="https://app-payment-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
    local notification_url="https://app-notification-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"

    local settings=(
        # Spring Boot port override (SERVER_PORT -> server.port)
        "SERVER_PORT=$port"
        # PostgreSQL datasource (Spring relaxed binding: SPRING_DATASOURCE_* -> spring.datasource.*)
        "SPRING_DATASOURCE_URL=$pg_jdbc_url"
        "SPRING_DATASOURCE_USERNAME=$pg_user"
        "SPRING_DATASOURCE_PASSWORD=$pg_password"
        # RabbitMQ (Spring relaxed binding: RABBITMQ_HOST -> rabbitmq.host)
        "RABBITMQ_HOST=$rabbitmq_host"
        "RABBITMQ_PORT=5672"
        "RABBITMQ_USERNAME=$rabbitmq_user"
        "RABBITMQ_PASSWORD=$rabbitmq_password"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # JWT (@Value("${jwt.secret}"), @Value("${jwt.issuer}"), @Value("${jwt.audience}"))
        "JWT_SECRET=$jwt_secret"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        # Downstream service URLs — two forms:
        #   1. SERVICES_*_URL: Spring relaxed binding for DaprServiceClient (@Value("${services.order.url}"))
        #   2. ORDER_SERVICE_URL etc.: read directly by ConfigurationService.getServiceUrls()
        "SERVICES_ORDER_URL=$order_url"
        "SERVICES_INVENTORY_URL=$inventory_url"
        "SERVICES_PAYMENT_URL=$payment_url"
        "SERVICES_NOTIFICATION_URL=$notification_url"
        "ORDER_SERVICE_URL=$order_url"
        "INVENTORY_SERVICE_URL=$inventory_url"
        "PAYMENT_SERVICE_URL=$payment_url"
        "NOTIFICATION_SERVICE_URL=$notification_url"
        # OpenTelemetry: telemetry is handled by the App Service Java agent
        # (ApplicationInsightsAgent_EXTENSION_VERSION=~3 set in _common.sh common_settings)
        # Disable Spring Boot micrometer tracing — pom.xml has only an opentelemetry-exporter-zipkin
        # dependency; no Azure OTEL exporter; leaving it enabled causes Zipkin connection errors
        # to localhost:9411 on App Service. OTEL_TRACES_EXPORTER is ignored by Spring micrometer.
        "MANAGEMENT_TRACING_ENABLED=false"
        "OTEL_SERVICE_NAME=order-processor-service"
        # Logging
        "LOG_LEVEL=INFO"
        "LOG_FORMAT=json"
        "LOG_TO_CONSOLE=true"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"

    # Add App Service outbound IPs to PostgreSQL firewall rules
    local app_name="app-${service_name}-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
    local outbound_ips
    outbound_ips=$(az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" \
        --query "outboundIpAddresses" -o tsv 2>/dev/null)
    if [ -n "$outbound_ips" ]; then
        print_info "Configuring PostgreSQL firewall rules for $app_name..."
        IFS=',' read -ra ip_list <<< "$outbound_ips"
        for ip in "${ip_list[@]}"; do
            ip=$(echo "$ip" | tr -d '[:space:]')
            rule_name="appservice-$(echo "$ip" | tr '.' '-')"
            az postgres flexible-server firewall-rule create \
                --name "$POSTGRESQL_SERVER" \
                --resource-group "$RESOURCE_GROUP" \
                --rule-name "$rule_name" \
                --start-ip-address "$ip" \
                --end-ip-address "$ip" \
                --output none 2>/dev/null || true
        done
        print_success "PostgreSQL firewall rules configured for $app_name"
    fi
}