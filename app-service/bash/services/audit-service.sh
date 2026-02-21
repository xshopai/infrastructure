#!/bin/bash
# =============================================================================
# Audit Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: PostgreSQL (Azure Flexible Server) - individual connection vars
# Port: 8080
# =============================================================================

deploy_audit_service() {
    local service_name="audit-service"
    local runtime="NODE|18-lts"
    local port="8080"

    # Load secrets from Key Vault
    local pg_url=$(load_secret "audit-service-postgres-url")
    local pg_user=$(load_secret "postgres-admin-user")
    local pg_password=$(load_secret "postgres-admin-password")
    local rabbitmq_url=$(load_secret "rabbitmq-url")
    # Parse PostgreSQL host from URL: postgresql://user:pass@HOST:5432/db
    local pg_host=$(echo "$pg_url" | sed 's|.*@\([^:/?]*\).*|\1|')

    local settings=(
        "POSTGRES_HOST=$pg_host"
        "POSTGRES_PORT=5432"
        "POSTGRES_DB=audit_service_db"
        "POSTGRES_USER=$pg_user"
        "POSTGRES_PASSWORD=$pg_password"
        "DB_SSL=true"
        "RABBITMQ_URL=$rabbitmq_url"
        "RABBITMQ_EXCHANGE=xshopai.events"
        "MESSAGING_PROVIDER=rabbitmq"
        # OpenTelemetry
        "OTEL_TRACES_EXPORTER=azure"
        "OTEL_SERVICE_NAME=audit-service"
    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}