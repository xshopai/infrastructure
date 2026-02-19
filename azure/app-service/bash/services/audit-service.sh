#!/bin/bash
# =============================================================================
# Audit Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: MongoDB (Cosmos DB)
# Port: 8010
# =============================================================================

deploy_audit_service() {
    local service_name="audit-service"
    local runtime="NODE|18-lts"
    local port="8010"
    
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"
        "MONGODB_DB_NAME=audit-service-db"
        "RABBITMQ_HOST=$RABBITMQ_HOST"
        "RABBITMQ_USER=$RABBITMQ_USER"
        "RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
