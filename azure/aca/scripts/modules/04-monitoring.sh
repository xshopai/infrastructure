#!/bin/bash

# =============================================================================
# Log Analytics & Application Insights Deployment Module
# =============================================================================
# Creates Log Analytics workspace and Application Insights for monitoring.
#
# Required Environment Variables:
#   - LOG_ANALYTICS: Name of the Log Analytics workspace
#   - APP_INSIGHTS: Name of the Application Insights resource
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#
# Exports:
#   - LOG_ANALYTICS_ID: Workspace ID for Container Apps
#   - LOG_ANALYTICS_KEY: Workspace key for Container Apps
#   - APP_INSIGHTS_CONNECTION_STRING: Connection string for telemetry
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

deploy_monitoring() {
    print_header "Creating Log Analytics & Application Insights"
    
    # Validate required variables
    validate_required_vars "LOG_ANALYTICS" "APP_INSIGHTS" "RESOURCE_GROUP" "LOCATION" || return 1
    
    # -------------------------------------------------------------------------
    # Log Analytics Workspace
    # -------------------------------------------------------------------------
    print_info "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "Log Analytics workspace already exists: $LOG_ANALYTICS"
    else
        # Create Log Analytics workspace with production configuration
        # 90-day retention and PerGB2018 pricing tier for production
        if az monitor log-analytics workspace create \
            --workspace-name "$LOG_ANALYTICS" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --retention-time 90 \
            --sku PerGB2018 \
            --output none 2>&1; then
            print_success "Log Analytics workspace created: $LOG_ANALYTICS"
        else
            print_error "Failed to create Log Analytics workspace: $LOG_ANALYTICS"
            return 1
        fi
    fi
    
    # Retrieve workspace properties
    export LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId -o tsv)
    
    export LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --workspace-name "$LOG_ANALYTICS" \
        --resource-group "$RESOURCE_GROUP" \
        --query primarySharedKey -o tsv)
    
    if [ -z "$LOG_ANALYTICS_ID" ] || [ -z "$LOG_ANALYTICS_KEY" ]; then
        print_error "Failed to retrieve Log Analytics properties"
        return 1
    fi
    
    print_info "Log Analytics Workspace ID: $LOG_ANALYTICS_ID"
    
    # -------------------------------------------------------------------------
    # Application Insights
    # -------------------------------------------------------------------------
    print_info "Creating Application Insights..."
    
    if az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_warning "Application Insights already exists: $APP_INSIGHTS"
    else
        # Build workspace resource ID (use variable to avoid Git Bash path mangling)
        local WORKSPACE_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS}"
        
        # MSYS_NO_PATHCONV=1 prevents Git Bash from converting /subscriptions/... to C:/Program Files/Git/subscriptions/...
        if MSYS_NO_PATHCONV=1 az monitor app-insights component create \
            --app "$APP_INSIGHTS" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind web \
            --application-type web \
            --workspace "$WORKSPACE_RESOURCE_ID" \
            --output none 2>&1; then
            print_success "Application Insights created: $APP_INSIGHTS"
        else
            print_error "Failed to create Application Insights: $APP_INSIGHTS"
            return 1
        fi
    fi
    
    # Retrieve connection string
    export APP_INSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)
    
    if [ -z "$APP_INSIGHTS_CONNECTION_STRING" ]; then
        print_error "Failed to retrieve Application Insights connection string"
        return 1
    fi
    
    print_info "Application Insights configured"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi
