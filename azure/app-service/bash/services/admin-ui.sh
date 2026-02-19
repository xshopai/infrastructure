#!/bin/bash
# =============================================================================
# Admin UI Deployment
# =============================================================================
# Runtime: Node.js 18 (React SPA)
# Database: None (Frontend)
# Port: 80
# =============================================================================

deploy_admin_ui() {
    local service_name="admin-ui"
    local runtime="NODE|18-lts"
    local port="80"
    
    local settings=(
        "REACT_APP_ADMIN_SERVICE_URL=https://app-admin-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "REACT_APP_AUTH_SERVICE_URL=https://app-auth-service-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
        "REACT_APP_ENVIRONMENT=$ENVIRONMENT"
    )
    
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
