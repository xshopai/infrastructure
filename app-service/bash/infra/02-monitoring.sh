#!/bin/bash

# =============================================================================
# Monitoring Module - Log Analytics & Application Insights
# =============================================================================
# Creates a shared Log Analytics workspace and a single Application Insights
# resource for the entire platform.
#
# Why One Shared App Insights:
#   - End-to-end distributed tracing across all microservices
#   - Single Application Map showing service dependencies
#   - Correlated logs using operation_Id
#   - Simpler management and lower cost
#
# Required Environment Variables:
#   - LOG_ANALYTICS: Name of the Log Analytics workspace
#   - APP_INSIGHTS: Name of the Application Insights resource
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#   - SUBSCRIPTION_ID: Azure subscription ID
#
# Exports:
#   - LOG_ANALYTICS_ID: Workspace ID
#   - APP_INSIGHTS_CONNECTION: Connection string for all services
#   - APP_INSIGHTS_KEY: Instrumentation key
# =============================================================================

set -e
# Sourced by deploy.sh - common.sh already loaded

deploy_monitoring() {
    print_header "Creating Monitoring Resources"
    
    validate_required_vars "LOG_ANALYTICS" "APP_INSIGHTS" "RESOURCE_GROUP" "LOCATION" "SUBSCRIPTION_ID" || return 1
    
    # -------------------------------------------------------------------------
    # Log Analytics Workspace
    # -------------------------------------------------------------------------
    print_info "Creating Log Analytics workspace: $LOG_ANALYTICS"
    
    if az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "Log Analytics already exists: $LOG_ANALYTICS"
    else
        if az monitor log-analytics workspace create \
            --workspace-name "$LOG_ANALYTICS" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --retention-time 30 \
            --output none; then
            print_success "Log Analytics created: $LOG_ANALYTICS"
        else
            print_error "Failed to create Log Analytics"
            return 1
        fi
    fi
    
    # Get workspace ID
    export LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId -o tsv)
    
    print_info "Log Analytics ID: $LOG_ANALYTICS_ID"
    
    # -------------------------------------------------------------------------
    # Application Insights (Shared across all services)
    # -------------------------------------------------------------------------
    print_info "Creating Application Insights: $APP_INSIGHTS"
    
    # Build workspace resource ID
    local WORKSPACE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS}"
    
    if az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "Application Insights already exists: $APP_INSIGHTS"
    else
        # MSYS_NO_PATHCONV=1 prevents Git Bash from converting /subscriptions/... paths
        if MSYS_NO_PATHCONV=1 az monitor app-insights component create \
            --app "$APP_INSIGHTS" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --workspace "$WORKSPACE_ID" \
            --kind web \
            --application-type web \
            --output none; then
            print_success "Application Insights created: $APP_INSIGHTS"
        else
            print_error "Failed to create Application Insights"
            return 1
        fi
    fi
    
    # Get connection string and instrumentation key
    export APP_INSIGHTS_CONNECTION=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)
    
    export APP_INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey -o tsv)
    
    print_success "Monitoring resources configured"
    print_info "App Insights Key: ${APP_INSIGHTS_KEY:0:20}..."
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi
