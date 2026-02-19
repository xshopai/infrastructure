#!/bin/bash
# =============================================================================
# Customer UI Deployment
# =============================================================================
# Runtime: Node.js 18 (React SPA)
# Database: None (Frontend)
# Port: 80
# =============================================================================

deploy_customer_ui() {
    local service_name="customer-ui"
    local runtime="NODE|18-lts"
    local port="80"
    
    local settings=(
        "REACT_APP_BFF_URL=https://app-web-bff-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "REACT_APP_ENVIRONMENT=$ENVIRONMENT"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
