#!/bin/bash

# =============================================================================
# Common Functions and Variables for xshopai Infrastructure Deployment
# =============================================================================
# This file contains shared utilities used by all deployment modules.
# Source this file at the beginning of each module script.
# =============================================================================

# -----------------------------------------------------------------------------
# Colors for output
# -----------------------------------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Print functions
# -----------------------------------------------------------------------------
print_header() {
    echo -e "\n${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==============================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# -----------------------------------------------------------------------------
# Helper function: Create role assignment using REST API
# Azure CLI's 'az role assignment create' has a known bug with MissingSubscription error
# This function uses the Azure REST API directly as a workaround
# -----------------------------------------------------------------------------
create_role_assignment() {
    local PRINCIPAL_ID="$1"
    local ROLE_NAME="$2"
    local SCOPE="$3"
    local PRINCIPAL_TYPE="${4:-ServicePrincipal}"
    
    # Get the role definition ID
    local ROLE_DEF_ID=""
    case "$ROLE_NAME" in
        "AcrPull")
            ROLE_DEF_ID="7f951dda-4ed3-4680-a7ca-43fe172d538d"
            ;;
        "Key Vault Secrets User")
            ROLE_DEF_ID="4633458b-17de-408a-b874-0445c86b69e6"
            ;;
        "Key Vault Secrets Officer")
            ROLE_DEF_ID="b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
            ;;
        *)
            print_error "Unknown role: $ROLE_NAME"
            return 1
            ;;
    esac
    
    # Generate a unique GUID for the assignment
    local UUID="$(openssl rand -hex 4)-$(openssl rand -hex 2)-$(openssl rand -hex 2)-$(openssl rand -hex 2)-$(openssl rand -hex 6)"
    
    # Create role assignment via REST API
    local FULL_ROLE_DEF_ID="/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleDefinitions/${ROLE_DEF_ID}"
    
    MSYS_NO_PATHCONV=1 az rest --method put \
        --uri "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignments/${UUID}?api-version=2022-04-01" \
        --body "{\"properties\": {\"roleDefinitionId\": \"${FULL_ROLE_DEF_ID}\", \"principalId\": \"${PRINCIPAL_ID}\", \"principalType\": \"${PRINCIPAL_TYPE}\"}}" \
        --output none 2>/dev/null
    
    return $?
}

# -----------------------------------------------------------------------------
# Resource naming helper
# Generates consistent resource names based on project, environment, and suffix
# -----------------------------------------------------------------------------
generate_resource_names() {
    local PROJECT_NAME="$1"
    local ENVIRONMENT="$2"
    local SUFFIX="$3"
    
    # Resources with hyphens allowed
    export RESOURCE_GROUP="rg-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export LOG_ANALYTICS="law-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export APP_INSIGHTS="appi-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export CONTAINER_ENV="cae-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export REDIS_NAME="redis-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export MYSQL_SERVER="mysql-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export SQL_SERVER="sql-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export POSTGRES_SERVER="psql-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export MANAGED_IDENTITY="id-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export SERVICE_BUS="sb-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export COSMOS_ACCOUNT="cosmos-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    export KEY_VAULT="kv-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
    
    # Resources without hyphens (naming restrictions)
    export ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}${SUFFIX}"
}

# -----------------------------------------------------------------------------
# Validate required variables are set
# Usage: validate_required_vars "VAR1" "VAR2" "VAR3"
# -----------------------------------------------------------------------------
validate_required_vars() {
    local missing=()
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required variables: ${missing[*]}"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Check if a resource exists
# Usage: resource_exists "resource_type" "name" "resource_group"
# Returns: 0 if exists, 1 if not
# -----------------------------------------------------------------------------
resource_exists() {
    local resource_type="$1"
    local name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "group")
            az group show --name "$name" &>/dev/null
            ;;
        "identity")
            az identity show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "acr")
            az acr show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "keyvault")
            az keyvault show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "redis")
            az redis show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "mysql")
            az mysql flexible-server show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "cosmos")
            az cosmosdb show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "servicebus")
            az servicebus namespace show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        "containerapp-env")
            az containerapp env show --name "$name" --resource-group "$resource_group" &>/dev/null
            ;;
        *)
            print_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}
