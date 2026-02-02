#!/bin/bash

# =============================================================================
# xshopai Infrastructure Status Checker
# =============================================================================
# Checks the health and status of all deployed Azure resources.
#
# Usage:
#   ./status.sh [environment] [suffix] [--parallel]
#
# Examples:
#   ./status.sh                    # Interactive mode (sequential)
#   ./status.sh dev abc1           # Check dev environment with suffix abc1
#   ./status.sh dev abc1 --parallel # Run checks in parallel (faster)
#
# Features:
#   - Resource existence check
#   - Health status for each resource
#   - Connection string validation
#   - Key Vault secrets inventory
#   - Dapr components status
#   - Parallel execution mode for faster checks
# =============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source common utilities
source "$MODULES_DIR/common.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ENVIRONMENT="${1:-}"
SUFFIX="${2:-}"
PARALLEL_MODE="${3:-}"
PROJECT_NAME="xshopai"

# Check for --parallel flag in any position
for arg in "$@"; do
    if [ "$arg" == "--parallel" ] || [ "$arg" == "-p" ]; then
        PARALLEL_MODE="--parallel"
    fi
done

# Remove --parallel from positional args
if [ "$ENVIRONMENT" == "--parallel" ] || [ "$ENVIRONMENT" == "-p" ]; then
    ENVIRONMENT=""
fi
if [ "$SUFFIX" == "--parallel" ] || [ "$SUFFIX" == "-p" ]; then
    SUFFIX=""
fi

# Temp directory for parallel results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Status tracking (will be aggregated from parallel results)
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# -----------------------------------------------------------------------------
# Status check helpers
# -----------------------------------------------------------------------------
# These helpers write to stdout normally, and track stats for both modes

check_pass() {
    echo -e "   ${GREEN}✓${NC} $1"
    # Track stats - either to file (parallel) or increment counter (sequential)
    if [ -n "${CHECK_STATS_FILE:-}" ]; then
        echo "PASS" >> "$CHECK_STATS_FILE"
    else
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
}

check_fail() {
    echo -e "   ${RED}✗${NC} $1"
    if [ -n "${CHECK_STATS_FILE:-}" ]; then
        echo "FAIL" >> "$CHECK_STATS_FILE"
    else
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

check_warn() {
    echo -e "   ${YELLOW}⚠${NC} $1"
    if [ -n "${CHECK_STATS_FILE:-}" ]; then
        echo "WARN" >> "$CHECK_STATS_FILE"
    else
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
}

check_info() {
    echo -e "   ${CYAN}ℹ${NC} $1"
}

section_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Aggregate stats from parallel check files
aggregate_stats() {
    local stats_dir="$1"
    shopt -s nullglob  # Handle no matches gracefully
    for f in "$stats_dir"/*.stats; do
        if [ -f "$f" ]; then
            while read -r line; do
                case "$line" in
                    PASS) PASSED_CHECKS=$((PASSED_CHECKS + 1)); TOTAL_CHECKS=$((TOTAL_CHECKS + 1)) ;;
                    FAIL) FAILED_CHECKS=$((FAILED_CHECKS + 1)); TOTAL_CHECKS=$((TOTAL_CHECKS + 1)) ;;
                    WARN) WARNINGS=$((WARNINGS + 1)); TOTAL_CHECKS=$((TOTAL_CHECKS + 1)) ;;
                esac
            done < "$f"
        fi
    done
}

# =============================================================================
# Prerequisites
# =============================================================================
print_header "xshopai Infrastructure Status Check"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Run: az login"
    exit 1
fi

# =============================================================================
# Environment Selection
# =============================================================================
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${CYAN}Available Environments:${NC}"
    echo "   dev  - Development"
    echo "   prod - Production"
    echo ""
    read -p "Enter environment (dev/prod) [dev]: " ENVIRONMENT
    ENVIRONMENT="${ENVIRONMENT:-dev}"
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

# =============================================================================
# Suffix Detection
# =============================================================================
if [ -z "$SUFFIX" ]; then
    # Try to find existing resource groups
    echo ""
    print_info "Searching for existing deployments..."
    
    EXISTING_RGS=$(az group list --query "[?starts_with(name, 'rg-${PROJECT_NAME}-${ENVIRONMENT}')].{name:name, suffix:tags.suffix}" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_RGS" ]; then
        echo ""
        echo -e "${CYAN}Found deployments:${NC}"
        while IFS=$'\t' read -r name suffix; do
            echo "   $name (suffix: $suffix)"
        done <<< "$EXISTING_RGS"
        echo ""
    fi
    
    read -p "Enter suffix: " SUFFIX
fi

if [ -z "$SUFFIX" ]; then
    print_error "Suffix is required"
    exit 1
fi

# Generate resource names
generate_resource_names "$PROJECT_NAME" "$ENVIRONMENT" "$SUFFIX"

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo ""
echo -e "${CYAN}Checking environment:${NC}"
echo "   Environment:   $ENVIRONMENT"
echo "   Suffix:        $SUFFIX"
echo "   Subscription:  $SUBSCRIPTION_NAME"
echo ""

# =============================================================================
# Resource Group Check
# =============================================================================
section_header "Resource Group"

if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Resource Group exists: $RESOURCE_GROUP"
    
    RG_LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
    check_info "Location: $RG_LOCATION"
    
    RG_TAGS=$(az group show --name "$RESOURCE_GROUP" --query tags -o json)
    check_info "Tags: $RG_TAGS"
else
    check_fail "Resource Group not found: $RESOURCE_GROUP"
    print_error "Cannot continue without resource group"
    exit 1
fi

# =============================================================================
# Parallel Execution Mode
# =============================================================================
# In parallel mode, we run independent checks concurrently for faster execution.
# Checks are written to temp files and displayed in order after completion.

if [ "$PARALLEL_MODE" == "--parallel" ]; then
    echo ""
    print_info "Running checks in PARALLEL mode..."
    echo ""
    
    # Define check functions that can run independently
    # Each function writes its output to a file and stats to a stats file
    
    run_check() {
        local check_name="$1"
        local output_file="$TEMP_DIR/${check_name}.out"
        local stats_file="$TEMP_DIR/${check_name}.stats"
        export CHECK_STATS_FILE="$stats_file"
        shift
        "$@" > "$output_file" 2>&1
    }
    
    # --- Check Functions ---
    
    check_managed_identity() {
        section_header "Managed Identity"
        if az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Managed Identity exists: $MANAGED_IDENTITY"
            IDENTITY_CLIENT_ID=$(az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
            IDENTITY_PRINCIPAL_ID=$(az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
            check_info "Client ID: $IDENTITY_CLIENT_ID"
            check_info "Principal ID: $IDENTITY_PRINCIPAL_ID"
            
            # Check Key Vault RBAC
            KV_ID=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
            if [ -n "$KV_ID" ]; then
                KV_ROLE=$(az rest --method get --url "https://management.azure.com${KV_ID}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
                    --query "value[?properties.principalId=='$IDENTITY_PRINCIPAL_ID' && contains(properties.roleDefinitionId, '4633458b-17de-408a-b874-0445c86b69e6')].id" -o tsv 2>/dev/null || echo "")
                if [ -n "$KV_ROLE" ]; then
                    check_pass "Key Vault Secrets User role assigned"
                else
                    check_fail "Key Vault Secrets User role NOT assigned"
                fi
            fi
            
            # Check Service Bus RBAC
            SB_ID=$(az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
            if [ -n "$SB_ID" ]; then
                SB_ROLE=$(az rest --method get --url "https://management.azure.com${SB_ID}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
                    --query "value[?properties.principalId=='$IDENTITY_PRINCIPAL_ID' && contains(properties.roleDefinitionId, '090c5cfd-751d-490a-894a-3ce6f1109419')].id" -o tsv 2>/dev/null || echo "")
                if [ -n "$SB_ROLE" ]; then
                    check_pass "Azure Service Bus Data Owner role assigned"
                else
                    check_fail "Azure Service Bus Data Owner role NOT assigned"
                fi
            fi
        else
            check_fail "Managed Identity not found: $MANAGED_IDENTITY"
        fi
    }
    
    check_acr() {
        section_header "Azure Container Registry"
        if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Container Registry exists: $ACR_NAME"
            ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
            check_info "Login Server: $ACR_LOGIN_SERVER"
            ACR_SKU=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query sku.name -o tsv)
            check_info "SKU: $ACR_SKU"
            IMAGE_COUNT=$(az acr repository list --name "$ACR_NAME" --output tsv 2>/dev/null | wc -l || echo "0")
            check_info "Repositories: $IMAGE_COUNT"
        else
            check_fail "Container Registry not found: $ACR_NAME"
        fi
    }
    
    check_monitoring() {
        section_header "Monitoring (Log Analytics & Application Insights)"
        if az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Log Analytics exists: $LOG_ANALYTICS"
        else
            check_fail "Log Analytics not found: $LOG_ANALYTICS"
        fi
        if az monitor app-insights component show --app "$APP_INSIGHTS" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Application Insights exists: $APP_INSIGHTS"
        else
            check_fail "Application Insights not found: $APP_INSIGHTS"
        fi
    }
    
    check_aca_env() {
        section_header "Container Apps Environment"
        if az containerapp env show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Container Apps Environment exists: $CONTAINER_ENV"
            ACA_STATUS=$(az containerapp env show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --query properties.provisioningState -o tsv)
            if [ "$ACA_STATUS" == "Succeeded" ]; then
                check_pass "Provisioning state: $ACA_STATUS"
            else
                check_warn "Provisioning state: $ACA_STATUS"
            fi
        else
            check_fail "Container Apps Environment not found: $CONTAINER_ENV"
        fi
    }
    
    check_servicebus() {
        section_header "Azure Service Bus"
        if az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Service Bus exists: $SERVICE_BUS"
            SB_STATUS=$(az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query status -o tsv)
            if [ "$SB_STATUS" == "Active" ]; then
                check_pass "Status: $SB_STATUS"
            else
                check_warn "Status: $SB_STATUS"
            fi
            TOPIC_COUNT=$(az servicebus topic list --namespace-name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query "length([])" -o tsv 2>/dev/null || echo "0")
            check_info "Topics: $TOPIC_COUNT"
        else
            check_fail "Service Bus not found: $SERVICE_BUS"
        fi
    }
    
    check_redis() {
        section_header "Azure Cache for Redis"
        if az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Redis Cache exists: $REDIS_NAME"
            REDIS_STATUS=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
            if [ "$REDIS_STATUS" == "Succeeded" ]; then
                check_pass "Provisioning state: $REDIS_STATUS"
            else
                check_warn "Provisioning state: $REDIS_STATUS"
            fi
        else
            check_fail "Redis Cache not found: $REDIS_NAME"
        fi
    }
    
    check_cosmos() {
        section_header "Azure Cosmos DB"
        if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Cosmos DB exists: $COSMOS_ACCOUNT"
            COSMOS_STATUS=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
            if [ "$COSMOS_STATUS" == "Succeeded" ]; then
                check_pass "Provisioning state: $COSMOS_STATUS"
            else
                check_warn "Provisioning state: $COSMOS_STATUS"
            fi
            COSMOS_PUBLIC=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query publicNetworkAccess -o tsv 2>/dev/null || echo "Unknown")
            if [ "$COSMOS_PUBLIC" == "Enabled" ]; then
                check_pass "Public network access: Enabled"
            else
                check_warn "Public network access: $COSMOS_PUBLIC"
            fi
            COSMOS_LOCAL_AUTH_DISABLED=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query disableLocalAuth -o tsv 2>/dev/null || echo "Unknown")
            if [ "$COSMOS_LOCAL_AUTH_DISABLED" == "false" ]; then
                check_pass "Local auth (connection strings): Enabled"
            elif [ "$COSMOS_LOCAL_AUTH_DISABLED" == "true" ]; then
                check_fail "Local auth (connection strings): DISABLED"
            else
                check_warn "Local auth status: Unknown"
            fi
        else
            check_fail "Cosmos DB not found: $COSMOS_ACCOUNT"
        fi
    }
    
    check_mysql() {
        section_header "Azure MySQL Flexible Server"
        if az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "MySQL Server exists: $MYSQL_SERVER"
            MYSQL_STATUS=$(az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
            if [ "$MYSQL_STATUS" == "Ready" ]; then
                check_pass "State: $MYSQL_STATUS"
            elif [ "$MYSQL_STATUS" == "Stopped" ]; then
                check_fail "State: $MYSQL_STATUS (Server is stopped!)"
            else
                check_warn "State: $MYSQL_STATUS"
            fi
        else
            check_fail "MySQL Server not found: $MYSQL_SERVER"
        fi
    }
    
    check_sql() {
        section_header "Azure SQL Server"
        if az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "SQL Server exists: $SQL_SERVER"
            SQL_STATE=$(az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
            check_info "State: $SQL_STATE"
        else
            check_fail "SQL Server not found: $SQL_SERVER"
        fi
    }
    
    check_postgres() {
        section_header "Azure PostgreSQL Flexible Server"
        if az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "PostgreSQL Server exists: $POSTGRES_SERVER"
            PG_STATUS=$(az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
            if [ "$PG_STATUS" == "Ready" ]; then
                check_pass "State: $PG_STATUS"
            else
                check_warn "State: $PG_STATUS"
            fi
        else
            check_fail "PostgreSQL Server not found: $POSTGRES_SERVER"
        fi
    }
    
    check_keyvault() {
        section_header "Azure Key Vault"
        if az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            check_pass "Key Vault exists: $KEY_VAULT"
            KV_PUBLIC=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query "properties.publicNetworkAccess" -o tsv 2>/dev/null || echo "Unknown")
            if [ "$KV_PUBLIC" == "Enabled" ]; then
                check_pass "Public network access: Enabled"
            else
                check_warn "Public network access: $KV_PUBLIC"
            fi
            SECRET_COUNT=$(az keyvault secret list --vault-name "$KEY_VAULT" --query "length([])" -o tsv 2>/dev/null || echo "0")
            check_info "Secrets: $SECRET_COUNT"
        else
            check_fail "Key Vault not found: $KEY_VAULT"
        fi
    }
    
    check_container_apps() {
        section_header "Deployed Container Apps"
        APPS=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, fqdn:properties.configuration.ingress.fqdn}" -o json 2>/dev/null || echo "[]")
        if [ "$APPS" != "[]" ]; then
            check_pass "Container Apps found"
            echo ""
            echo -e "   ${CYAN}Apps:${NC}"
            echo "$APPS" | jq -r '.[] | "      - \(.name): https://\(.fqdn // "no-ingress")"'
        else
            check_info "No Container Apps deployed yet"
        fi
    }
    
    # Export functions and variables for subshells
    export -f check_pass check_fail check_warn check_info section_header
    export -f check_managed_identity check_acr check_monitoring check_aca_env
    export -f check_servicebus check_redis check_cosmos check_mysql check_sql
    export -f check_postgres check_keyvault check_container_apps
    export TEMP_DIR RESOURCE_GROUP MANAGED_IDENTITY KEY_VAULT SERVICE_BUS
    export ACR_NAME LOG_ANALYTICS APP_INSIGHTS CONTAINER_ENV REDIS_NAME
    export COSMOS_ACCOUNT MYSQL_SERVER SQL_SERVER POSTGRES_SERVER
    export GREEN RED YELLOW CYAN BLUE NC
    
    # Start time
    START_TIME=$(date +%s)
    
    # Run all checks in parallel
    echo -e "${CYAN}Starting parallel checks...${NC}"
    
    run_check "01_identity" check_managed_identity &
    run_check "02_acr" check_acr &
    run_check "03_monitoring" check_monitoring &
    run_check "04_aca_env" check_aca_env &
    run_check "05_servicebus" check_servicebus &
    run_check "06_redis" check_redis &
    run_check "07_cosmos" check_cosmos &
    run_check "08_mysql" check_mysql &
    run_check "09_sql" check_sql &
    run_check "10_postgres" check_postgres &
    run_check "11_keyvault" check_keyvault &
    run_check "12_apps" check_container_apps &
    
    # Wait for all background jobs
    wait
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    print_success "All checks completed in ${DURATION} seconds"
    echo ""
    
    # Display results in order
    for f in "$TEMP_DIR"/*.out; do
        if [ -f "$f" ]; then
            cat "$f"
        fi
    done
    
    # Aggregate statistics
    aggregate_stats "$TEMP_DIR"
    
else
    # Sequential mode (original behavior)
section_header "Managed Identity"

if az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Managed Identity exists: $MANAGED_IDENTITY"
    
    IDENTITY_CLIENT_ID=$(az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
    IDENTITY_PRINCIPAL_ID=$(az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
    check_info "Client ID: $IDENTITY_CLIENT_ID"
    check_info "Principal ID: $IDENTITY_PRINCIPAL_ID"
    
    # Check Key Vault RBAC assignment (Key Vault Secrets User = 4633458b-17de-408a-b874-0445c86b69e6)
    print_info "Checking Key Vault RBAC..."
    KV_ID=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
    if [ -n "$KV_ID" ]; then
        KV_ROLE=$(az rest --method get --url "https://management.azure.com${KV_ID}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
            --query "value[?properties.principalId=='$IDENTITY_PRINCIPAL_ID' && contains(properties.roleDefinitionId, '4633458b-17de-408a-b874-0445c86b69e6')].id" -o tsv 2>/dev/null || echo "")
        if [ -n "$KV_ROLE" ]; then
            check_pass "Key Vault Secrets User role assigned"
        else
            check_fail "Key Vault Secrets User role NOT assigned (Dapr secretstore will fail!)"
        fi
    fi
    
    # Check Service Bus RBAC assignment (Azure Service Bus Data Owner = 090c5cfd-751d-490a-894a-3ce6f1109419)
    print_info "Checking Service Bus RBAC..."
    SB_ID=$(az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
    if [ -n "$SB_ID" ]; then
        SB_ROLE=$(az rest --method get --url "https://management.azure.com${SB_ID}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
            --query "value[?properties.principalId=='$IDENTITY_PRINCIPAL_ID' && contains(properties.roleDefinitionId, '090c5cfd-751d-490a-894a-3ce6f1109419')].id" -o tsv 2>/dev/null || echo "")
        if [ -n "$SB_ROLE" ]; then
            check_pass "Azure Service Bus Data Owner role assigned"
        else
            check_fail "Azure Service Bus Data Owner role NOT assigned (Dapr pubsub will fail!)"
        fi
    fi
else
    check_fail "Managed Identity not found: $MANAGED_IDENTITY"
fi

# =============================================================================
# Container Registry Check
# =============================================================================
section_header "Azure Container Registry"

if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Container Registry exists: $ACR_NAME"
    
    ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
    check_info "Login Server: $ACR_LOGIN_SERVER"
    
    ACR_SKU=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query sku.name -o tsv)
    check_info "SKU: $ACR_SKU"
    
    # Check for images
    IMAGE_COUNT=$(az acr repository list --name "$ACR_NAME" --output tsv 2>/dev/null | wc -l || echo "0")
    check_info "Repositories: $IMAGE_COUNT"
else
    check_fail "Container Registry not found: $ACR_NAME"
fi

# =============================================================================
# Log Analytics & App Insights Check
# =============================================================================
section_header "Monitoring (Log Analytics & Application Insights)"

if az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Log Analytics exists: $LOG_ANALYTICS"
else
    check_fail "Log Analytics not found: $LOG_ANALYTICS"
fi

if az monitor app-insights component show --app "$APP_INSIGHTS" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Application Insights exists: $APP_INSIGHTS"
    
    APP_INSIGHTS_KEY=$(az monitor app-insights component show --app "$APP_INSIGHTS" --resource-group "$RESOURCE_GROUP" --query instrumentationKey -o tsv)
    check_info "Instrumentation Key: ${APP_INSIGHTS_KEY:0:8}..."
else
    check_fail "Application Insights not found: $APP_INSIGHTS"
fi

# =============================================================================
# Container Apps Environment Check
# =============================================================================
section_header "Container Apps Environment"

if az containerapp env show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Container Apps Environment exists: $CONTAINER_ENV"
    
    CAE_STATUS=$(az containerapp env show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --query properties.provisioningState -o tsv)
    if [ "$CAE_STATUS" == "Succeeded" ]; then
        check_pass "Provisioning state: $CAE_STATUS"
    else
        check_warn "Provisioning state: $CAE_STATUS"
    fi
    
    # Check deployed apps
    APP_COUNT=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "length([?properties.environmentId contains '$CONTAINER_ENV'])" -o tsv 2>/dev/null || echo "0")
    check_info "Deployed apps: $APP_COUNT"
else
    check_fail "Container Apps Environment not found: $CONTAINER_ENV"
fi

# =============================================================================
# Service Bus Check
# =============================================================================
section_header "Azure Service Bus"

if az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Service Bus exists: $SERVICE_BUS"
    
    SB_STATUS=$(az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query status -o tsv)
    if [ "$SB_STATUS" == "Active" ]; then
        check_pass "Status: $SB_STATUS"
    else
        check_warn "Status: $SB_STATUS"
    fi
    
    SB_SKU=$(az servicebus namespace show --name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query sku.name -o tsv)
    check_info "SKU: $SB_SKU"
    
    # Count queues/topics
    QUEUE_COUNT=$(az servicebus queue list --namespace-name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query "length([])" -o tsv 2>/dev/null || echo "0")
    TOPIC_COUNT=$(az servicebus topic list --namespace-name "$SERVICE_BUS" --resource-group "$RESOURCE_GROUP" --query "length([])" -o tsv 2>/dev/null || echo "0")
    check_info "Queues: $QUEUE_COUNT, Topics: $TOPIC_COUNT"
else
    check_fail "Service Bus not found: $SERVICE_BUS"
fi

# =============================================================================
# Redis Cache Check
# =============================================================================
section_header "Azure Cache for Redis"

if az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Redis Cache exists: $REDIS_NAME"
    
    REDIS_STATUS=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
    if [ "$REDIS_STATUS" == "Succeeded" ]; then
        check_pass "Provisioning state: $REDIS_STATUS"
    else
        check_warn "Provisioning state: $REDIS_STATUS"
    fi
    
    REDIS_HOST=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query hostName -o tsv)
    check_info "Host: $REDIS_HOST"
    
    REDIS_SKU=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query sku.name -o tsv)
    check_info "SKU: $REDIS_SKU"
else
    check_fail "Redis Cache not found: $REDIS_NAME"
fi

# =============================================================================
# Cosmos DB Check
# =============================================================================
section_header "Azure Cosmos DB"

if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Cosmos DB exists: $COSMOS_ACCOUNT"
    
    COSMOS_STATUS=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
    if [ "$COSMOS_STATUS" == "Succeeded" ]; then
        check_pass "Provisioning state: $COSMOS_STATUS"
    else
        check_warn "Provisioning state: $COSMOS_STATUS"
    fi
    
    COSMOS_KIND=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query kind -o tsv)
    check_info "API: $COSMOS_KIND"
    
    # Check public network access
    COSMOS_PUBLIC=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query publicNetworkAccess -o tsv 2>/dev/null || echo "Unknown")
    if [ "$COSMOS_PUBLIC" == "Enabled" ]; then
        check_pass "Public network access: Enabled"
    else
        check_warn "Public network access: $COSMOS_PUBLIC (services may not be able to connect)"
    fi
    
    # Check local auth (connection strings) - CRITICAL for seeding and local dev
    COSMOS_LOCAL_AUTH_DISABLED=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query disableLocalAuth -o tsv 2>/dev/null || echo "Unknown")
    if [ "$COSMOS_LOCAL_AUTH_DISABLED" == "false" ]; then
        check_pass "Local auth (connection strings): Enabled"
    elif [ "$COSMOS_LOCAL_AUTH_DISABLED" == "true" ]; then
        check_fail "Local auth (connection strings): DISABLED"
        check_info "  → Seeding and local dev will fail with 'Unauthorized' errors"
        check_info "  → Fix: az cosmosdb update --name $COSMOS_ACCOUNT -g $RESOURCE_GROUP --disable-key-based-metadata-write-access false"
    else
        check_warn "Local auth status: Unknown ($COSMOS_LOCAL_AUTH_DISABLED)"
    fi
    
    # Count databases
    DB_COUNT=$(az cosmosdb mongodb database list --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query "length([])" -o tsv 2>/dev/null || echo "0")
    check_info "Databases: $DB_COUNT"
else
    check_fail "Cosmos DB not found: $COSMOS_ACCOUNT"
fi

# =============================================================================
# MySQL Check
# =============================================================================
section_header "Azure MySQL Flexible Server"

if az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "MySQL Server exists: $MYSQL_SERVER"
    
    MYSQL_STATUS=$(az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
    if [ "$MYSQL_STATUS" == "Ready" ]; then
        check_pass "State: $MYSQL_STATUS"
    elif [ "$MYSQL_STATUS" == "Stopped" ]; then
        check_fail "State: $MYSQL_STATUS (Server is stopped! Run: az mysql flexible-server start --name $MYSQL_SERVER -g $RESOURCE_GROUP)"
    else
        check_warn "State: $MYSQL_STATUS"
    fi
    
    # Check public network access
    MYSQL_PUBLIC=$(az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query network.publicNetworkAccess -o tsv 2>/dev/null || echo "Unknown")
    if [ "$MYSQL_PUBLIC" == "Enabled" ]; then
        check_pass "Public network access: Enabled"
    else
        check_warn "Public network access: $MYSQL_PUBLIC"
    fi
    
    MYSQL_HOST=$(az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv)
    check_info "Host: $MYSQL_HOST"
    
    MYSQL_VERSION=$(az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query version -o tsv)
    check_info "Version: $MYSQL_VERSION"
    
    # Count databases
    DB_COUNT=$(az mysql flexible-server db list --server-name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query "length([])" -o tsv 2>/dev/null || echo "0")
    check_info "Databases: $DB_COUNT"
else
    check_fail "MySQL Server not found: $MYSQL_SERVER"
fi

# =============================================================================
# SQL Server Check
# =============================================================================
section_header "Azure SQL Server"

if az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "SQL Server exists: $SQL_SERVER"
    
    SQL_HOST=$(az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv)
    check_info "Host: $SQL_HOST"
    
    SQL_VERSION=$(az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" --query version -o tsv)
    check_info "Version: $SQL_VERSION"
    
    # Count databases
    DB_COUNT=$(az sql db list --server "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" --query "length([?name!='master'])" -o tsv 2>/dev/null || echo "0")
    check_info "Databases: $DB_COUNT"
else
    check_fail "SQL Server not found: $SQL_SERVER"
fi

# =============================================================================
# PostgreSQL Check
# =============================================================================
section_header "Azure PostgreSQL Flexible Server"

if az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "PostgreSQL Server exists: $POSTGRES_SERVER"
    
    POSTGRES_STATUS=$(az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
    if [ "$POSTGRES_STATUS" == "Ready" ]; then
        check_pass "State: $POSTGRES_STATUS"
    else
        check_warn "State: $POSTGRES_STATUS"
    fi
    
    POSTGRES_HOST=$(az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv)
    check_info "Host: $POSTGRES_HOST"
    
    POSTGRES_VERSION=$(az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" --query version -o tsv)
    check_info "Version: $POSTGRES_VERSION"
else
    check_fail "PostgreSQL Server not found: $POSTGRES_SERVER"
fi

# =============================================================================
# Key Vault Check
# =============================================================================
section_header "Azure Key Vault"

if az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Key Vault exists: $KEY_VAULT"
    
    KV_URL=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query properties.vaultUri -o tsv)
    check_info "URL: $KV_URL"
    
    # Check network access - CRITICAL for Dapr secretstore
    KV_PUBLIC_ACCESS=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query properties.publicNetworkAccess -o tsv 2>/dev/null || echo "Unknown")
    if [ "$KV_PUBLIC_ACCESS" == "Enabled" ]; then
        check_pass "Public network access: Enabled"
    else
        check_fail "Public network access: $KV_PUBLIC_ACCESS (Dapr secretstore will fail! Run: az keyvault update --name $KEY_VAULT -g $RESOURCE_GROUP --public-network-access Enabled)"
    fi
    
    # Check RBAC authorization mode
    KV_RBAC=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query properties.enableRbacAuthorization -o tsv 2>/dev/null || echo "false")
    if [ "$KV_RBAC" == "true" ]; then
        check_pass "RBAC authorization: Enabled"
    else
        check_warn "RBAC authorization: Disabled (using access policies instead)"
    fi
    
    # Try to list secrets
    print_info "Checking secrets access..."
    SECRET_LIST=$(az keyvault secret list --vault-name "$KEY_VAULT" --query "[].name" -o tsv 2>/dev/null || echo "ACCESS_DENIED")
    
    if [ "$SECRET_LIST" == "ACCESS_DENIED" ]; then
        check_warn "Cannot list secrets (access denied or network restriction)"
    else
        SECRET_COUNT=$(echo "$SECRET_LIST" | grep -c . || echo "0")
        check_pass "Secrets accessible: $SECRET_COUNT secrets found"
        
        # List secret names
        echo ""
        echo -e "   ${CYAN}Secrets:${NC}"
        echo "$SECRET_LIST" | while read -r secret; do
            echo "      - $secret"
        done
    fi
else
    check_fail "Key Vault not found: $KEY_VAULT"
fi

# =============================================================================
# Dapr Components Check
# =============================================================================
section_header "Dapr Components"

if az containerapp env show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    DAPR_COMPONENTS=$(az containerapp env dapr-component list --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$DAPR_COMPONENTS" ]; then
        check_pass "Dapr components configured"
        
        # Get managed identity client ID for validation
        EXPECTED_CLIENT_ID=$(az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv 2>/dev/null || echo "")
        
        echo ""
        echo -e "   ${CYAN}Components:${NC}"
        echo "$DAPR_COMPONENTS" | while read -r component; do
            COMP_TYPE=$(az containerapp env dapr-component show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --dapr-component-name "$component" --query properties.componentType -o tsv 2>/dev/null || echo "unknown")
            echo "      - $component ($COMP_TYPE)"
        done
        
        # Validate secretstore configuration
        echo ""
        print_info "Validating secretstore configuration..."
        SECRETSTORE_VAULT=$(az containerapp env dapr-component show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --dapr-component-name secretstore --query "properties.metadata[?name=='vaultName'].value | [0]" -o tsv 2>/dev/null || echo "")
        SECRETSTORE_CLIENT=$(az containerapp env dapr-component show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --dapr-component-name secretstore --query "properties.metadata[?name=='azureClientId'].value | [0]" -o tsv 2>/dev/null || echo "")
        
        if [ "$SECRETSTORE_VAULT" == "$KEY_VAULT" ]; then
            check_pass "Secretstore vaultName: $SECRETSTORE_VAULT (correct)"
        elif [ -n "$SECRETSTORE_VAULT" ]; then
            check_fail "Secretstore vaultName: $SECRETSTORE_VAULT (expected: $KEY_VAULT)"
        else
            check_fail "Secretstore vaultName not configured"
        fi
        
        if [ "$SECRETSTORE_CLIENT" == "$EXPECTED_CLIENT_ID" ]; then
            check_pass "Secretstore azureClientId: matches managed identity"
        elif [ -n "$SECRETSTORE_CLIENT" ]; then
            check_warn "Secretstore azureClientId: $SECRETSTORE_CLIENT (expected: $EXPECTED_CLIENT_ID)"
        else
            check_fail "Secretstore azureClientId not configured (using connection string?)"
        fi
        
        # Validate pubsub configuration
        print_info "Validating pubsub configuration..."
        PUBSUB_CLIENT=$(az containerapp env dapr-component show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --dapr-component-name pubsub --query "properties.metadata[?name=='azureClientId'].value | [0]" -o tsv 2>/dev/null || echo "")
        PUBSUB_NS=$(az containerapp env dapr-component show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --dapr-component-name pubsub --query "properties.metadata[?name=='namespaceName'].value | [0]" -o tsv 2>/dev/null || echo "")
        
        if [ "$PUBSUB_CLIENT" == "$EXPECTED_CLIENT_ID" ]; then
            check_pass "Pubsub uses managed identity authentication"
        elif [ -n "$PUBSUB_CLIENT" ]; then
            check_warn "Pubsub azureClientId: $PUBSUB_CLIENT (expected: $EXPECTED_CLIENT_ID)"
        else
            check_warn "Pubsub may be using connection string instead of managed identity"
        fi
        
        if [ -n "$PUBSUB_NS" ]; then
            check_info "Pubsub namespace: $PUBSUB_NS"
        fi
    else
        check_warn "No Dapr components found"
    fi
else
    check_warn "Cannot check Dapr components (Container Apps Environment not found)"
fi

# =============================================================================
# Deployed Container Apps
# =============================================================================
section_header "Deployed Container Apps"

APPS=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, fqdn:properties.configuration.ingress.fqdn, replicas:properties.template.scale.minReplicas}" -o json 2>/dev/null || echo "[]")

if [ "$APPS" != "[]" ]; then
    check_pass "Container Apps found"
    echo ""
    echo -e "   ${CYAN}Apps:${NC}"
    echo "$APPS" | jq -r '.[] | "      - \(.name): https://\(.fqdn // "no-ingress")"'
else
    check_info "No Container Apps deployed yet"
fi

fi  # End of parallel/sequential mode if-else

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  STATUS SUMMARY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "   Total checks:  $TOTAL_CHECKS"
echo -e "   ${GREEN}Passed:${NC}        $PASSED_CHECKS"
echo -e "   ${YELLOW}Warnings:${NC}      $WARNINGS"
echo -e "   ${RED}Failed:${NC}        $FAILED_CHECKS"
echo ""

if [ $FAILED_CHECKS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All infrastructure resources are healthy!${NC}"
elif [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Infrastructure is operational with some warnings${NC}"
else
    echo -e "${RED}❌ Some resources have issues that need attention${NC}"
fi

echo ""
echo -e "${CYAN}Quick Commands:${NC}"
echo -e "   View resource group:  ${BLUE}az group show -n $RESOURCE_GROUP${NC}"
echo -e "   List all resources:   ${BLUE}az resource list -g $RESOURCE_GROUP -o table${NC}"
echo -e "   Open Azure Portal:    ${BLUE}az portal -g $RESOURCE_GROUP${NC}"
echo ""

# Exit with appropriate code
if [ $FAILED_CHECKS -gt 0 ]; then
    exit 1
fi
exit 0
