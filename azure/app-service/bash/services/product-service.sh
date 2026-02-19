#!/bin/bash
# =============================================================================
# Product Service Deployment
# =============================================================================
# Runtime: Python 3.11 (FastAPI)
# Database: MongoDB (Cosmos DB) - product-service database
# Port: 8001
# =============================================================================

deploy_product_service() {
    local service_name="product-service"
    local runtime="PYTHON|3.11"
    local port="8001"

    # Load secrets from Key Vault
    local mongodb_uri=$(load_secret "product-service-mongodb-uri")
    local rabbitmq_url=$(load_secret "rabbitmq-url")

    local settings=(
        "MONGODB_URI=$mongodb_uri"
        "MONGODB_DB_NAME=product_service_db"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        "NAME=product-service"
        "API_VERSION=1.0.0"
