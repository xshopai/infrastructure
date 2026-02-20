#!/bin/bash
# =============================================================================
# Inventory Service Deployment
# =============================================================================
# Runtime: Python 3.11 (Flask)
# Database: MySQL (Azure Flexible Server)
# Port: 8005
# Code reads MYSQL_SERVER_CONNECTION (server URL without DB) + DB_NAME separately
# =============================================================================

deploy_inventory_service() {
    local service_name="inventory-service"
    local runtime="PYTHON|3.11"
    local port="8005"

    # Load secrets from Key Vault
    local mysql_server=$(load_secret "inventory-service-mysql-server")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local jwt_algorithm=$(load_secret "jwt-algorithm")
    local service_product_token=$(load_secret "admin-service-token")
    local service_order_token=$(load_secret "order-service-token")
    local service_cart_token=$(load_secret "cart-service-token")
    local service_webbff_token=$(load_secret "web-bff-token")

    local settings=(
        # Database
        "MYSQL_SERVER_CONNECTION=$mysql_server"
        "DB_NAME=inventory_service_db"
        # Messaging
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # JWT Authentication
        "JWT_SECRET=$jwt_secret"
        "JWT_ALGORITHM=$jwt_algorithm"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        # Service-to-Service Tokens
        "SERVICE_PRODUCT_TOKEN=$service_product_token"
        "SERVICE_ORDER_TOKEN=$service_order_token"
        "SERVICE_CART_TOKEN=$service_cart_token"
        "SERVICE_WEBBFF_TOKEN=$service_webbff_token"
        # OpenTelemetry (Azure Application Insights)
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=inventory-service"
        # Logging
        "LOG_LEVEL=INFO"
        "LOG_FORMAT=json"
        "LOG_TO_CONSOLE=true"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"

    # Add App Service outbound IPs to MySQL firewall rules
    local app_name="app-${service_name}-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
    local outbound_ips
    outbound_ips=$(az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" \
        --query "outboundIpAddresses" -o tsv 2>/dev/null)
    if [ -n "$outbound_ips" ]; then
        print_info "Configuring MySQL firewall rules for $app_name..."
        IFS=',' read -ra ip_list <<< "$outbound_ips"
        for ip in "${ip_list[@]}"; do
            ip=$(echo "$ip" | tr -d '[:space:]')
            rule_name="appservice-$(echo "$ip" | tr '.' '-')"
            az mysql flexible-server firewall-rule create \
                --name "$MYSQL_SERVER" \
                --resource-group "$RESOURCE_GROUP" \
                --rule-name "$rule_name" \
                --start-ip-address "$ip" \
                --end-ip-address "$ip" \
                --output none 2>/dev/null || true
        done
        print_success "MySQL firewall rules configured for $app_name"
    fi
}
