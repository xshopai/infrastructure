#!/bin/bash
# =============================================================================
# Chat Service Deployment
# =============================================================================
# Runtime: Node.js 18
# Database: None
# Port: 8013
# Uses Azure OpenAI for AI chat; calls other services via direct HTTP
# =============================================================================

deploy_chat_service() {
    local service_name="chat-service"
    local runtime="NODE|18-lts"
    local port="8013"

    # Load secrets from Key Vault
    local jwt_secret=$(load_secret "jwt-secret")
    local jwt_algorithm=$(load_secret "jwt-algorithm")
    local jwt_issuer=$(load_secret "jwt-issuer")
    local jwt_audience=$(load_secret "jwt-audience")
    local openai_endpoint=$(load_secret "chat-service-openai-endpoint")
    local openai_api_key=$(load_secret "chat-service-openai-api-key")
    local openai_deployment=$(load_secret "chat-service-openai-deployment")

    local settings=(
        "NODE_ENV=$ENVIRONMENT"
        "JWT_SECRET=$jwt_secret"
        "JWT_ALGORITHM=$jwt_algorithm"
        "JWT_ISSUER=$jwt_issuer"
        "JWT_AUDIENCE=$jwt_audience"
        "AZURE_OPENAI_ENDPOINT=$openai_endpoint"
        "AZURE_OPENAI_API_KEY=$openai_api_key"
        "AZURE_OPENAI_DEPLOYMENT_NAME=$openai_deployment"
        "AZURE_OPENAI_API_VERSION=2024-02-15-preview"
        "MESSAGING_PROVIDER=rabbitmq"
        # Downstream service URLs for direct HTTP calls
        "PRODUCT_SERVICE_URL=https://app-product-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "ORDER_SERVICE_URL=https://app-order-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "INVENTORY_SERVICE_URL=https://app-inventory-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"

    )

    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}