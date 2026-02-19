#!/bin/bash
# =============================================================================
# Notification Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB)
# Port: 8011
# =============================================================================

deploy_notification_service() {
    local service_name="notification-service"
    local runtime="NODE|18-lts"
    local port="8011"
    
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"
        "MONGODB_DB_NAME=notification-service-db"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
        "SMTP_HOST=${SMTP_HOST:-}"
        "SMTP_PORT=${SMTP_PORT:-587}"
        "SMTP_USER=${SMTP_USER:-}"
        "SMTP_PASSWORD=${SMTP_PASSWORD:-}"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
