#!/bin/bash

# =============================================================================
# Log Analytics & Application Insights Deployment Module
# =============================================================================
# Creates Log Analytics workspace and per-service Application Insights resources.
#
# Architecture Decision:
#   Each service gets its own Application Insights resource for:
#   - Clean separation of telemetry per service
#   - Independent configuration, retention, and access control
#   - Easier troubleshooting and performance analysis
#   - Scalable observability as the platform grows
#
# Required Environment Variables:
#   - LOG_ANALYTICS: Name of the Log Analytics workspace
#   - APP_INSIGHTS_PREFIX: Prefix for App Insights resources (e.g., appi-xshopai-dev-abc1)
#   - RESOURCE_GROUP: Resource group name
#   - LOCATION: Azure region
#   - XSHOPAI_SERVICES: Array of service names (from common.sh)
#
# Exports:
#   - LOG_ANALYTICS_ID: Workspace ID for Container Apps
#   - LOG_ANALYTICS_KEY: Workspace key for Container Apps
#   - APP_INSIGHTS_CONNECTIONS: Associative array of service -> connection string
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Declare associative array to store per-service connection strings
declare -A APP_INSIGHTS_CONNECTIONS
export APP_INSIGHTS_CONNECTIONS

deploy_monitoring() {
    print_header "Creating Log Analytics & Per-Service Application Insights"
    
    # Validate required variables
    validate_required_vars "LOG_ANALYTICS" "APP_INSIGHTS_PREFIX" "RESOURCE_GROUP" "LOCATION" || return 1
    
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
    # Per-Service Application Insights
    # -------------------------------------------------------------------------
    print_info "Creating Application Insights for each service..."
    
    # Build workspace resource ID (use variable to avoid Git Bash path mangling)
    local WORKSPACE_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS}"
    
    local CREATED_COUNT=0
    local EXISTING_COUNT=0
    
    for SERVICE in "${XSHOPAI_SERVICES[@]}"; do
        # Generate App Insights name: appi-xshopai-dev-abc1-admin-service
        local APP_INSIGHTS_NAME="${APP_INSIGHTS_PREFIX}-${SERVICE}"
        
        print_info "Processing App Insights for: $SERVICE"
        
        if az monitor app-insights component show \
            --app "$APP_INSIGHTS_NAME" \
            --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            print_warning "  Already exists: $APP_INSIGHTS_NAME"
            EXISTING_COUNT=$((EXISTING_COUNT + 1))
        else
            # MSYS_NO_PATHCONV=1 prevents Git Bash from converting /subscriptions/... to C:/Program Files/Git/subscriptions/...
            if MSYS_NO_PATHCONV=1 az monitor app-insights component create \
                --app "$APP_INSIGHTS_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --location "$LOCATION" \
                --kind web \
                --application-type web \
                --workspace "$WORKSPACE_RESOURCE_ID" \
                --tags "service=$SERVICE" "environment=$ENVIRONMENT" \
                --output none 2>&1; then
                print_success "  Created: $APP_INSIGHTS_NAME"
                CREATED_COUNT=$((CREATED_COUNT + 1))
            else
                print_error "  Failed to create: $APP_INSIGHTS_NAME"
                # Continue with other services, don't fail completely
            fi
        fi
        
        # Retrieve connection string for this service
        local CONNECTION_STRING=$(az monitor app-insights component show \
            --app "$APP_INSIGHTS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query connectionString -o tsv 2>/dev/null || echo "")
        
        if [ -n "$CONNECTION_STRING" ]; then
            APP_INSIGHTS_CONNECTIONS["$SERVICE"]="$CONNECTION_STRING"
        else
            print_warning "  Could not retrieve connection string for: $SERVICE"
        fi
    done
    
    print_info "Application Insights Summary:"
    print_info "  Created: $CREATED_COUNT"
    print_info "  Existing: $EXISTING_COUNT"
    print_info "  Total: ${#APP_INSIGHTS_CONNECTIONS[@]} connection strings retrieved"
    
    return 0
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_monitoring
fi
