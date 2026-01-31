#!/bin/bash

# =============================================================================
# xshopai Infrastructure Status Checker
# =============================================================================
# Checks the health and status of all deployed Azure resources.
#
# Usage:
#   ./status.sh [environment] [suffix]
#
# Examples:
#   ./status.sh                    # Interactive mode
#   ./status.sh dev abc1           # Check dev environment with suffix abc1
#
# Features:
#   - Resource existence check
#   - Health status for each resource
#   - Connection string validation
#   - Key Vault secrets inventory
#   - Dapr components status
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
PROJECT_NAME="xshopai"

# Status tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# -----------------------------------------------------------------------------
# Status check helpers
# -----------------------------------------------------------------------------
check_pass() {
    echo -e "   ${GREEN}✓${NC} $1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

check_fail() {
    echo -e "   ${RED}✗${NC} $1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

check_warn() {
    echo -e "   ${YELLOW}⚠${NC} $1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
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
# Managed Identity Check
# =============================================================================
section_header "Managed Identity"

if az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    check_pass "Managed Identity exists: $MANAGED_IDENTITY"
    
    IDENTITY_CLIENT_ID=$(az identity show --name "$MANAGED_IDENTITY" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
    check_info "Client ID: $IDENTITY_CLIENT_ID"
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
    else
        check_warn "State: $MYSQL_STATUS"
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
    
    # Check network access
    KV_PUBLIC_ACCESS=$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query properties.publicNetworkAccess -o tsv 2>/dev/null || echo "Unknown")
    if [ "$KV_PUBLIC_ACCESS" == "Enabled" ]; then
        check_pass "Public network access: Enabled"
    else
        check_warn "Public network access: $KV_PUBLIC_ACCESS (may need manual access for portal/CLI)"
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
        echo ""
        echo -e "   ${CYAN}Components:${NC}"
        echo "$DAPR_COMPONENTS" | while read -r component; do
            COMP_TYPE=$(az containerapp env dapr-component show --name "$CONTAINER_ENV" --resource-group "$RESOURCE_GROUP" --dapr-component-name "$component" --query componentType -o tsv 2>/dev/null || echo "unknown")
            echo "      - $component ($COMP_TYPE)"
        done
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
