#!/bin/bash
# =============================================================================
# Inventory Service Deployment
# =============================================================================
# Runtime: Python 3.11 (Flask)
# Database: MySQL (Azure Flexible Server)
# Port: 8004
# Code reads MYSQL_SERVER_CONNECTION (server URL without DB) + DB_NAME separately
# =============================================================================

deploy_inventory_service() {
    local service_name="inventory-service"
    local runtime="PYTHON|3.11"
    local port="8004"

    # Load secrets from Key Vault
    # inventory-service-mysql-server = mysql+pymysql://user:pass@host:3306 (no DB name)
    local mysql_server=$(load_secret "inventory-service-mysql-server")
    local rabbitmq_url=$(load_secret "rabbitmq-url")

    local settings=(
        "MYSQL_SERVER_CONNECTION=$mysql_server"
        "DB_NAME=inventory_service_db"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
