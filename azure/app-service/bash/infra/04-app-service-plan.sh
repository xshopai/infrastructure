#!/bin/bash
# =============================================================================
# App Service Plan Module
# =============================================================================

deploy_app_service_plan() {
    print_header "Creating App Service Plan"
    
    validate_required_vars "APP_SERVICE_PLAN" "RESOURCE_GROUP" "LOCATION" || return 1
    
    if resource_exists "appservice-plan" "$APP_SERVICE_PLAN" "$RESOURCE_GROUP"; then
        print_warning "App Service Plan already exists: $APP_SERVICE_PLAN"
    else
        print_info "Creating App Service Plan: $APP_SERVICE_PLAN"
        
        # Use P3v3 for both dev and production
        local SKU="P3V3"
        
        if az appservice plan create \
            --name "$APP_SERVICE_PLAN" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku "$SKU" \
            --is-linux \
            --output none; then
            print_success "App Service Plan created: $APP_SERVICE_PLAN ($SKU)"
        else
            print_error "Failed to create App Service Plan"
            return 1
        fi
    fi
    
    # Get App Service Plan ID
    export APP_SERVICE_PLAN_ID=$(az appservice plan show \
        --name "$APP_SERVICE_PLAN" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)
    
    print_success "App Service Plan configured"
}
