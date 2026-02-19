#!/bin/bash
# =============================================================================
# Notification Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None (stateless, consumes events and sends emails/SMS)
# Port: 8011
# =============================================================================

deploy_notification_service() {
    local service_name="notification-service"
    local runtime="NODE|18-lts"
    local port="8011"

    # Load secrets from Key Vault
    local rabbitmq_url=$(load_secret "rabbitmq-url")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # SMTP configuration - set these via Azure Portal or update KV after deployment
        "SMTP_HOST=${SMTP_HOST:-}"
        "SMTP_PORT=${SMTP_PORT:-587}"
        "SMTP_USER=${SMTP_USER:-}"
        "SMTP_PASS=${SMTP_PASS:-}"
        "SMTP_SECURE=${SMTP_SECURE:-false}"
        "EMAIL_FROM_ADDRESS=${EMAIL_FROM_ADDRESS:-noreply@xshopai.com}"
        "EMAIL_FROM_NAME=${EMAIL_FROM_NAME:-xShopAI}"
        "EMAIL_ENABLED=${EMAIL_ENABLED:-false}"
        "EMAIL_PROVIDER=${EMAIL_PROVIDER:-smtp}"
