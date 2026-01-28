#!/bin/bash

# =============================================================================
# xshopai Infrastructure Deployment Script for Azure Container Apps
# =============================================================================
# This script deploys all shared infrastructure resources required by the
# xshopai microservices platform on Azure Container Apps.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Sufficient permissions to create resources in the subscription
#
# Usage:
#   ./deploy-infra.sh [environment] [subscription] [location] [suffix]
#   
#   environment:  dev (default), staging, or prod
#   subscription: Azure subscription ID or name (will prompt if not provided)
#   location:     Azure region (will prompt if not provided)
#   suffix:       Unique suffix for globally-scoped resources (will prompt if not provided)
#
# Example:
#   ./deploy-infra.sh dev
#   ./deploy-infra.sh dev "My Subscription" swedencentral
#   ./deploy-infra.sh dev "My Subscription" swedencentral abc1
#   ./deploy-infra.sh prod 12345678-1234-1234-1234-123456789abc westus2 prod01
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Colors for output
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
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

# Progress tracking
TOTAL_STEPS=9
CURRENT_STEP=0
SCRIPT_START_TIME=0

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local ELAPSED=0
    if [ $SCRIPT_START_TIME -gt 0 ]; then
        ELAPSED=$((SECONDS - SCRIPT_START_TIME))
    fi
    echo -e "\n${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}[$CURRENT_STEP/$TOTAL_STEPS] $1${NC} ${CYAN}(${ELAPSED}s elapsed)${NC}"
    echo -e "${BLUE}==============================================================================${NC}\n"
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
    # MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from mangling paths starting with /
    local FULL_ROLE_DEF_ID="/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleDefinitions/${ROLE_DEF_ID}"
    
    MSYS_NO_PATHCONV=1 az rest --method put \
        --uri "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignments/${UUID}?api-version=2022-04-01" \
        --body "{\"properties\": {\"roleDefinitionId\": \"${FULL_ROLE_DEF_ID}\", \"principalId\": \"${PRINCIPAL_ID}\", \"principalType\": \"${PRINCIPAL_TYPE}\"}}" \
        --output none 2>/dev/null
    
    return $?
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ENVIRONMENT="${1:-}"
SUBSCRIPTION="${2:-}"
LOCATION="${3:-}"
SUFFIX="${4:-}"
PROJECT_NAME="xshopai"

# =============================================================================
# Prerequisites Check
# =============================================================================
print_header "Checking Prerequisites"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
print_success "Azure CLI is installed"

# Check if openssl is available (for generating random suffix)
if ! command -v openssl &> /dev/null; then
    print_warning "openssl is not installed. Will use fallback for random suffix generation."
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    print_warning "Not logged into Azure. Initiating login..."
    az login
fi
print_success "Logged into Azure"

# Register required resource providers
print_info "Registering required resource providers..."
az provider register --namespace Microsoft.Sql --wait 2>/dev/null || true
print_success "Resource providers registered"

# =============================================================================
# Environment Selection
# =============================================================================
print_header "Environment Configuration"

echo -e "${CYAN}Available Environments:${NC}"
echo "   dev     - Development environment"
echo "   staging - Staging/QA environment"
echo "   prod    - Production environment"
echo ""

if [ -z "$ENVIRONMENT" ]; then
    read -p "Enter environment (dev/staging/prod) [dev]: " ENVIRONMENT
    ENVIRONMENT="${ENVIRONMENT:-dev}"
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    echo "   Valid values: dev, staging, prod"
    exit 1
fi
print_success "Environment: $ENVIRONMENT"

# =============================================================================
# Azure Subscription Selection
# =============================================================================
print_header "Azure Subscription Configuration"

# List available subscriptions
echo -e "${CYAN}Available Azure Subscriptions:${NC}"
az account list --query "[].{Name:name, SubscriptionId:id, IsDefault:isDefault}" --output table

echo ""
if [ -z "$SUBSCRIPTION" ]; then
    read -p "Enter Azure Subscription ID (leave empty for default): " SUBSCRIPTION
fi

if [ -n "$SUBSCRIPTION" ]; then
    az account set --subscription "$SUBSCRIPTION"
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_success "Subscription set to: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
else
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_info "Using default subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
fi

# =============================================================================
# Azure Location Selection
# =============================================================================
print_header "Azure Location Configuration"

echo -e "${CYAN}Common Azure Locations:${NC}"
echo "   eastus        - East US (Virginia)"
echo "   eastus2       - East US 2 (Virginia)"
echo "   westus        - West US (California)"
echo "   westus2       - West US 2 (Washington)"
echo "   westus3       - West US 3 (Arizona)"
echo "   centralus     - Central US (Iowa)"
echo "   northeurope   - North Europe (Ireland)"
echo "   westeurope    - West Europe (Netherlands)"
echo "   swedencentral - Sweden Central"
echo "   uksouth       - UK South (London)"
echo "   southeastasia - Southeast Asia (Singapore)"
echo "   australiaeast - Australia East (Sydney)"
echo ""

if [ -z "$LOCATION" ]; then
    read -p "Enter Azure Location [swedencentral]: " LOCATION
    LOCATION="${LOCATION:-swedencentral}"
fi

# Validate location
if ! az account list-locations --query "[?name=='$LOCATION'].name" -o tsv | grep -q "$LOCATION"; then
    print_error "Invalid location: $LOCATION"
    echo "   Run 'az account list-locations -o table' to see all valid locations."
    exit 1
fi
print_success "Using location: $LOCATION"

# =============================================================================
# Unique Suffix Configuration
# =============================================================================
print_header "Unique Suffix for Globally-Scoped Resources"

echo -e "${CYAN}Some Azure resources require globally unique names.${NC}"
echo "A suffix helps avoid naming conflicts, especially after deletions."
echo "Examples: abc1, dev01, team1, jd01"
echo ""

# Generate default suffix
if command -v openssl &> /dev/null; then
    DEFAULT_SUFFIX=$(openssl rand -hex 2)
else
    DEFAULT_SUFFIX=$(date +%s | tail -c 5)
fi

if [ -z "$SUFFIX" ]; then
    read -p "Enter unique suffix (3-6 alphanumeric) [$DEFAULT_SUFFIX]: " SUFFIX
    SUFFIX="${SUFFIX:-$DEFAULT_SUFFIX}"
fi

# Validate suffix (alphanumeric, 3-6 characters)
if [[ ! "$SUFFIX" =~ ^[a-z0-9]{3,6}$ ]]; then
    print_error "Invalid suffix: $SUFFIX"
    echo "   Suffix must be 3-6 lowercase alphanumeric characters."
    exit 1
fi
print_success "Using suffix: $SUFFIX"

# =============================================================================
# Deployment Summary
# =============================================================================
print_header "xshopai Infrastructure Deployment"

echo -e "${CYAN}Configuration:${NC}"
echo "   Environment:   $ENVIRONMENT"
echo "   Subscription:  $SUBSCRIPTION_NAME"
echo "   Location:      $LOCATION"
echo "   Suffix:        $SUFFIX"

# -----------------------------------------------------------------------------
# Resource Naming (following Azure naming conventions)
# -----------------------------------------------------------------------------
# All resources include suffix for uniqueness and easier identification
# Some resources (ACR, Storage) don't allow hyphens in names
# -----------------------------------------------------------------------------

# Resources with hyphens allowed
RESOURCE_GROUP="rg-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
LOG_ANALYTICS="law-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
APP_INSIGHTS="appi-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
CONTAINER_ENV="cae-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
REDIS_NAME="redis-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
MYSQL_SERVER="mysql-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
SQL_SERVER="sql-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
POSTGRES_SERVER="psql-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
MANAGED_IDENTITY="id-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
SERVICE_BUS="sb-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
COSMOS_ACCOUNT="cosmos-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"
KEY_VAULT="kv-${PROJECT_NAME}-${ENVIRONMENT}-${SUFFIX}"

# Resources without hyphens (naming restrictions)
ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}${SUFFIX}"                    # No hyphens allowed

echo ""
echo -e "${CYAN}Resources to be created (suffix: $SUFFIX):${NC}"
echo ""
echo -e "   ${YELLOW}Infrastructure Resources:${NC}"
echo "   ─────────────────────────────────────────"
echo "   Resource Group:      $RESOURCE_GROUP"
echo "   Managed Identity:    $MANAGED_IDENTITY"
echo "   Container Registry:  $ACR_NAME"
echo "   Log Analytics:       $LOG_ANALYTICS"
echo "   Application Insights: $APP_INSIGHTS"
echo "   Container Apps Env:  $CONTAINER_ENV"
echo ""
echo -e "   ${YELLOW}Data & Messaging Resources:${NC}"
echo "   ─────────────────────────────────────────"
echo "   Service Bus:         $SERVICE_BUS"
echo "   Redis Cache:         $REDIS_NAME"
echo "   Cosmos DB:           $COSMOS_ACCOUNT"
echo "   MySQL Server:        $MYSQL_SERVER"
echo "   SQL Server:          $SQL_SERVER"
echo "   PostgreSQL Server:   $POSTGRES_SERVER"
echo "   Key Vault:           $KEY_VAULT"
echo ""

# Confirm before proceeding
read -p "Do you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Deployment cancelled."
    exit 1
fi

# Start timing
SCRIPT_START_TIME=$SECONDS
echo ""
print_info "Starting deployment at $(date '+%H:%M:%S')..."

# =============================================================================
# 1. Create Resource Group
# =============================================================================
print_step "Creating Resource Group"
if az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags "project=$PROJECT_NAME" "environment=$ENVIRONMENT" "suffix=$SUFFIX" \
    --output none 2>&1; then
    print_success "Resource Group created: $RESOURCE_GROUP"
else
    print_error "Failed to create Resource Group: $RESOURCE_GROUP"
    exit 1
fi

# =============================================================================
# 2. Create User-Assigned Managed Identity
# =============================================================================
print_step "Creating Managed Identity"
if az identity create \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none 2>&1; then
    print_success "Managed Identity created: $MANAGED_IDENTITY"
else
    print_error "Failed to create Managed Identity: $MANAGED_IDENTITY"
    exit 1
fi

IDENTITY_ID=$(az identity show \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)

IDENTITY_CLIENT_ID=$(az identity show \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --query clientId -o tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)

if [ -z "$IDENTITY_ID" ] || [ -z "$IDENTITY_CLIENT_ID" ] || [ -z "$IDENTITY_PRINCIPAL_ID" ]; then
    print_error "Failed to retrieve Managed Identity properties"
    exit 1
fi
print_info "Identity ID: $IDENTITY_ID"

# =============================================================================
# 3. Create ACR, Log Analytics, App Insights - PARALLEL
# =============================================================================
print_step "Creating ACR, Log Analytics, App Insights (parallel)"
print_info "Starting parallel creation of quick resources..."

# Start ACR creation in background
az acr create \
    --name "$ACR_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Basic \
    --admin-enabled true \
    --output none 2>/tmp/acr_error.log &
ACR_PID=$!

# Start Log Analytics creation in background
az monitor log-analytics workspace create \
    --workspace-name "$LOG_ANALYTICS" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none 2>/tmp/law_error.log &
LAW_PID=$!

# Wait for both to complete
ACR_OK=false
LAW_OK=false

wait $ACR_PID && ACR_OK=true || ACR_OK=false
wait $LAW_PID && LAW_OK=true || LAW_OK=false

# Verify ACR
if [ "$ACR_OK" = true ]; then
    print_success "Container Registry created: $ACR_NAME"
else
    print_error "Failed to create Container Registry: $ACR_NAME"
    cat /tmp/acr_error.log
    exit 1
fi

ACR_LOGIN_SERVER=$(az acr show \
    --name "$ACR_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query loginServer -o tsv)

if [ -z "$ACR_LOGIN_SERVER" ]; then
    print_error "Failed to retrieve ACR login server"
    exit 1
fi
print_info "Login Server: $ACR_LOGIN_SERVER"

# Grant managed identity access to ACR
print_info "Granting managed identity ACR pull access..."
ACR_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"
if create_role_assignment "$IDENTITY_PRINCIPAL_ID" "AcrPull" "$ACR_SCOPE" "ServicePrincipal"; then
    print_success "ACR role assignment created"
else
    print_warning "ACR role assignment may already exist (continuing)"
fi

# Verify Log Analytics
if [ "$LAW_OK" = true ]; then
    print_success "Log Analytics Workspace created: $LOG_ANALYTICS"
else
    print_error "Failed to create Log Analytics Workspace: $LOG_ANALYTICS"
    cat /tmp/law_error.log
    exit 1
fi

LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
    --workspace-name "$LOG_ANALYTICS" \
    --resource-group "$RESOURCE_GROUP" \
    --query customerId -o tsv)

LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --workspace-name "$LOG_ANALYTICS" \
    --resource-group "$RESOURCE_GROUP" \
    --query primarySharedKey -o tsv)

if [ -z "$LOG_ANALYTICS_ID" ] || [ -z "$LOG_ANALYTICS_KEY" ]; then
    print_error "Failed to retrieve Log Analytics credentials"
    exit 1
fi
print_info "Workspace ID: $LOG_ANALYTICS_ID"

# Get Log Analytics resource ID for Application Insights
LOG_ANALYTICS_RESOURCE_ID=$(az monitor log-analytics workspace show \
    --workspace-name "$LOG_ANALYTICS" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)

# Now create App Insights (depends on Log Analytics)
print_info "Creating Application Insights (depends on Log Analytics)..."
if MSYS_NO_PATHCONV=1 az monitor app-insights component create \
    --app "$APP_INSIGHTS" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind web \
    --application-type web \
    --workspace "$LOG_ANALYTICS_RESOURCE_ID" \
    --output none 2>&1; then
    print_success "Application Insights created: $APP_INSIGHTS"
else
    print_error "Failed to create Application Insights: $APP_INSIGHTS"
    exit 1
fi

APP_INSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
    --app "$APP_INSIGHTS" \
    --resource-group "$RESOURCE_GROUP" \
    --query connectionString -o tsv)

APP_INSIGHTS_INSTRUMENTATION_KEY=$(az monitor app-insights component show \
    --app "$APP_INSIGHTS" \
    --resource-group "$RESOURCE_GROUP" \
    --query instrumentationKey -o tsv)

if [ -z "$APP_INSIGHTS_CONNECTION_STRING" ] || [ -z "$APP_INSIGHTS_INSTRUMENTATION_KEY" ]; then
    print_error "Failed to retrieve Application Insights credentials"
    exit 1
fi
print_info "Instrumentation Key: ${APP_INSIGHTS_INSTRUMENTATION_KEY:0:8}..."

# =============================================================================
# 4. Create Container Apps Environment
# =============================================================================
print_step "Creating Container Apps Environment"
print_warning "This may take 2-5 minutes..."
if az containerapp env create \
    --name "$CONTAINER_ENV" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --logs-workspace-id "$LOG_ANALYTICS_ID" \
    --logs-workspace-key "$LOG_ANALYTICS_KEY" \
    --output none 2>&1; then
    print_success "Container Apps Environment created: $CONTAINER_ENV"
else
    print_error "Failed to create Container Apps Environment: $CONTAINER_ENV"
    exit 1
fi

# =============================================================================
# 5. Create Azure Service Bus Namespace
# =============================================================================
print_step "Creating Service Bus Namespace"
if az servicebus namespace create \
    --name "$SERVICE_BUS" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard \
    --output none 2>&1; then
    print_success "Service Bus Namespace created: $SERVICE_BUS"
else
    print_error "Failed to create Service Bus Namespace: $SERVICE_BUS"
    exit 1
fi

SERVICE_BUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
    --namespace-name "$SERVICE_BUS" \
    --resource-group "$RESOURCE_GROUP" \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString -o tsv)

if [ -z "$SERVICE_BUS_CONNECTION" ]; then
    print_error "Failed to retrieve Service Bus connection string"
    exit 1
fi
print_info "Connection string retrieved"

# Configure Service Bus network rules - allow Azure services
print_info "Configuring Service Bus network rules..."
if az servicebus namespace network-rule-set update \
    --namespace-name "$SERVICE_BUS" \
    --resource-group "$RESOURCE_GROUP" \
    --default-action Allow \
    --enable-trusted-service-access true \
    --output none 2>/dev/null; then
    print_success "Service Bus network rules configured"
else
    print_warning "Service Bus network rules configuration skipped (may not be supported on Standard tier)"
fi

# =============================================================================
# 6. Create Data Resources IN PARALLEL (Redis, Cosmos DB, MySQL, SQL Server, PostgreSQL)
# =============================================================================
# These resources take the longest to provision (10-15 minutes each)
# Running them in parallel reduces total deployment time significantly
# Sequential: ~50 min | Parallel: ~15 min (time of longest resource)
# =============================================================================

print_step "Creating Data Resources (Redis, Cosmos DB, MySQL, SQL Server, PostgreSQL)"
print_warning "Starting all five resources in parallel to save time..."
print_info "This will take approximately 10-15 minutes total (instead of 50+ minutes sequential)"
echo ""

# Generate MySQL password upfront (needed for parallel creation)
MYSQL_ADMIN_USER="xshopaiadmin"
MYSQL_ADMIN_PASSWORD="XShop$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')!"

# Generate PostgreSQL password upfront (needed for parallel creation)
POSTGRES_ADMIN_USER="pgadmin"
POSTGRES_ADMIN_PASSWORD="PgShop$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')!"

# Get current user info for SQL Server Azure AD admin (MCAPS requires AD-only auth)
SQL_AD_ADMIN_SID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
SQL_AD_ADMIN_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "")

# Track start time
PARALLEL_START=$SECONDS

# -----------------------------------------------------------------------------
# Start Redis creation in background
# -----------------------------------------------------------------------------
print_info "Starting Redis Cache creation..."
az redis create \
    --name "$REDIS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Basic \
    --vm-size c0 \
    --output none 2>/tmp/redis_error.log &
REDIS_PID=$!

# -----------------------------------------------------------------------------
# Start Cosmos DB creation in background
# -----------------------------------------------------------------------------
print_info "Starting Cosmos DB creation..."
az cosmosdb create \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --kind MongoDB \
    --server-version "4.2" \
    --default-consistency-level Session \
    --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=false \
    --enable-automatic-failover true \
    --disable-key-based-metadata-write-access false \
    --output none 2>/tmp/cosmos_error.log &
COSMOS_PID=$!

# Enable local (key-based) authentication for Cosmos DB after creation
# Some Azure environments/policies disable this by default
(
    # Wait for Cosmos DB to be created
    wait $COSMOS_PID
    if [ $? -eq 0 ]; then
        print_info "Ensuring Cosmos DB local authentication is enabled..."
        MSYS_NO_PATHCONV=1 az resource update \
            --ids "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOS_ACCOUNT}" \
            --set properties.disableLocalAuth=false \
            --output none 2>/dev/null || true
    fi
) &
COSMOS_AUTH_PID=$!

# -----------------------------------------------------------------------------
# Start MySQL creation in background
# -----------------------------------------------------------------------------
print_info "Starting MySQL Flexible Server creation..."
az mysql flexible-server create \
    --name "$MYSQL_SERVER" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --admin-user "$MYSQL_ADMIN_USER" \
    --admin-password "$MYSQL_ADMIN_PASSWORD" \
    --sku-name Standard_B1ms \
    --tier Burstable \
    --storage-size 32 \
    --version "8.0.21" \
    --public-access 0.0.0.0 \
    --output none 2>/tmp/mysql_error.log &
MYSQL_PID=$!

# -----------------------------------------------------------------------------
# Start PostgreSQL creation in background
# -----------------------------------------------------------------------------
print_info "Starting PostgreSQL Flexible Server creation..."
az postgres flexible-server create \
    --name "$POSTGRES_SERVER" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --admin-user "$POSTGRES_ADMIN_USER" \
    --admin-password "$POSTGRES_ADMIN_PASSWORD" \
    --sku-name Standard_B1ms \
    --tier Burstable \
    --storage-size 32 \
    --version "15" \
    --public-access 0.0.0.0 \
    --output none 2>/tmp/postgres_error.log &
POSTGRES_PID=$!

# -----------------------------------------------------------------------------
# Start SQL Server creation in background (Azure AD-only auth for MCAPS compliance)
# -----------------------------------------------------------------------------
print_info "Starting Azure SQL Server creation..."
if [ -n "$SQL_AD_ADMIN_SID" ] && [ -n "$SQL_AD_ADMIN_NAME" ]; then
    az sql server create \
        --name "$SQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --enable-ad-only-auth \
        --external-admin-principal-type User \
        --external-admin-name "$SQL_AD_ADMIN_NAME" \
        --external-admin-sid "$SQL_AD_ADMIN_SID" \
        --output none 2>/tmp/sql_error.log &
    SQL_PID=$!
else
    print_warning "Could not get Azure AD user info - SQL Server creation may fail"
    az sql server create \
        --name "$SQL_SERVER" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none 2>/tmp/sql_error.log &
    SQL_PID=$!
fi

echo ""
print_info "All five resources are now provisioning in parallel..."
print_info "PIDs: Redis=$REDIS_PID, Cosmos=$COSMOS_PID, MySQL=$MYSQL_PID, PostgreSQL=$POSTGRES_PID, SQL=$SQL_PID"
echo ""

# -----------------------------------------------------------------------------
# Monitor progress of all five resources
# -----------------------------------------------------------------------------
REDIS_DONE=false
COSMOS_DONE=false
MYSQL_DONE=false
POSTGRES_DONE=false
SQL_DONE=false
REDIS_STATUS="⏳ Creating"
COSMOS_STATUS="⏳ Creating"
MYSQL_STATUS="⏳ Creating"
POSTGRES_STATUS="⏳ Creating"
SQL_STATUS="⏳ Creating"

while [ "$REDIS_DONE" = false ] || [ "$COSMOS_DONE" = false ] || [ "$MYSQL_DONE" = false ] || [ "$POSTGRES_DONE" = false ] || [ "$SQL_DONE" = false ]; do
    ELAPSED=$((SECONDS - PARALLEL_START))
    
    # Check Redis
    if [ "$REDIS_DONE" = false ]; then
        if ! kill -0 $REDIS_PID 2>/dev/null; then
            wait $REDIS_PID
            if [ $? -eq 0 ]; then
                REDIS_STATUS="✅ Done"
            else
                REDIS_STATUS="❌ Failed"
            fi
            REDIS_DONE=true
        else
            # Check actual state
            REDIS_STATE=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv 2>/dev/null || echo "Creating")
            if [ "$REDIS_STATE" = "Succeeded" ]; then
                REDIS_STATUS="✅ Done"
                REDIS_DONE=true
            elif [ "$REDIS_STATE" = "Failed" ]; then
                REDIS_STATUS="❌ Failed"
                REDIS_DONE=true
            else
                REDIS_STATUS="⏳ $REDIS_STATE"
            fi
        fi
    fi
    
    # Check Cosmos DB
    if [ "$COSMOS_DONE" = false ]; then
        if ! kill -0 $COSMOS_PID 2>/dev/null; then
            wait $COSMOS_PID
            if [ $? -eq 0 ]; then
                COSMOS_STATUS="✅ Done"
            else
                COSMOS_STATUS="❌ Failed"
            fi
            COSMOS_DONE=true
        fi
    fi
    
    # Check MySQL
    if [ "$MYSQL_DONE" = false ]; then
        if ! kill -0 $MYSQL_PID 2>/dev/null; then
            wait $MYSQL_PID
            if [ $? -eq 0 ]; then
                MYSQL_STATUS="✅ Done"
            else
                MYSQL_STATUS="❌ Failed"
            fi
            MYSQL_DONE=true
        fi
    fi
    
    # Check PostgreSQL
    if [ "$POSTGRES_DONE" = false ]; then
        if ! kill -0 $POSTGRES_PID 2>/dev/null; then
            wait $POSTGRES_PID
            if [ $? -eq 0 ]; then
                POSTGRES_STATUS="✅ Done"
            else
                POSTGRES_STATUS="❌ Failed"
            fi
            POSTGRES_DONE=true
        fi
    fi
    
    # Check SQL Server
    if [ "$SQL_DONE" = false ]; then
        if ! kill -0 $SQL_PID 2>/dev/null; then
            wait $SQL_PID
            if [ $? -eq 0 ]; then
                SQL_STATUS="✅ Done"
            else
                SQL_STATUS="❌ Failed"
            fi
            SQL_DONE=true
        fi
    fi
    
    # Print status
    printf "\r   ⏱️  %3ds | Redis: %-12s | Cosmos: %-12s | MySQL: %-12s | Postgres: %-12s | SQL: %-12s" \
        "$ELAPSED" "$REDIS_STATUS" "$COSMOS_STATUS" "$MYSQL_STATUS" "$POSTGRES_STATUS" "$SQL_STATUS"
    
    if [ "$REDIS_DONE" = false ] || [ "$COSMOS_DONE" = false ] || [ "$MYSQL_DONE" = false ] || [ "$POSTGRES_DONE" = false ] || [ "$SQL_DONE" = false ]; then
        sleep 10
    fi
done

PARALLEL_ELAPSED=$((SECONDS - PARALLEL_START))
echo ""
echo ""
print_success "All data resources completed in ${PARALLEL_ELAPSED} seconds"

# -----------------------------------------------------------------------------
# Verify and retrieve Redis details (still part of step 5)
# -----------------------------------------------------------------------------
print_info "Retrieving Redis credentials..."
REDIS_HOST=$(az redis show \
    --name "$REDIS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query hostName -o tsv 2>/dev/null)

if [ -z "$REDIS_HOST" ]; then
    print_error "Redis creation failed. Check /tmp/redis_error.log"
    cat /tmp/redis_error.log
    exit 1
fi

REDIS_KEY=$(az redis list-keys \
    --name "$REDIS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query primaryKey -o tsv)

REDIS_PORT="6380"
print_success "Redis Cache ready: $REDIS_HOST:$REDIS_PORT"

# -----------------------------------------------------------------------------
# Verify and retrieve Cosmos DB details (still part of step 5)
# -----------------------------------------------------------------------------
print_info "Retrieving Cosmos DB credentials..."

# Verify Cosmos DB was created
COSMOS_STATE=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv 2>/dev/null)
if [ "$COSMOS_STATE" != "Succeeded" ]; then
    print_error "Cosmos DB creation failed. Check /tmp/cosmos_error.log"
    cat /tmp/cosmos_error.log
    exit 1
fi

# Enable local authentication (connection string based auth) for dev/staging
# This allows services and seeders to connect using connection strings
# Production should use managed identity where possible
if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "staging" ]]; then
    print_info "Enabling local authentication on Cosmos DB for $ENVIRONMENT environment..."
    MSYS_NO_PATHCONV=1 az resource update \
        --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DocumentDB/databaseAccounts/$COSMOS_ACCOUNT" \
        --set properties.disableLocalAuth=false \
        --output none 2>/dev/null || print_warning "Could not enable local auth (may already be enabled)"
fi

COSMOS_CONNECTION=$(az cosmosdb keys list \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --type connection-strings \
    --query "connectionStrings[0].connectionString" -o tsv)

if [ -z "$COSMOS_CONNECTION" ]; then
    print_error "Failed to retrieve Cosmos DB connection string"
    exit 1
fi
print_success "Cosmos DB ready: $COSMOS_ACCOUNT.mongo.cosmos.azure.com"

# Note: Individual databases are created by each service during deployment
# This ensures services own their data and can manage their own schemas

# -----------------------------------------------------------------------------
# Verify and retrieve MySQL details (still part of step 5)
# -----------------------------------------------------------------------------
print_info "Retrieving MySQL details..."

MYSQL_HOST=$(az mysql flexible-server show \
    --name "$MYSQL_SERVER" \
    --resource-group "$RESOURCE_GROUP" \
    --query fullyQualifiedDomainName -o tsv 2>/dev/null)

if [ -z "$MYSQL_HOST" ]; then
    print_error "MySQL creation failed. Check /tmp/mysql_error.log"
    cat /tmp/mysql_error.log
    exit 1
fi

# Configure MySQL firewall rules
print_info "Configuring MySQL firewall rules..."
if az mysql flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MYSQL_SERVER" \
    --rule-name "AllowAllAzureServices" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none 2>/dev/null; then
    print_success "MySQL firewall rule created: AllowAllAzureServices"
else
    print_warning "MySQL firewall rule may already exist (continuing)"
fi

# For dev/staging environments, allow deployer's IP for seeding and debugging
if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "staging" ]]; then
    MY_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")
    if [ -n "$MY_IP" ]; then
        print_info "Adding firewall rule for deployer IP: $MY_IP"
        if az mysql flexible-server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$MYSQL_SERVER" \
            --rule-name "AllowDeployerIP" \
            --start-ip-address "$MY_IP" \
            --end-ip-address "$MY_IP" \
            --output none 2>/dev/null; then
            print_success "MySQL firewall rule created: AllowDeployerIP ($MY_IP)"
        else
            print_warning "Could not add deployer IP rule (continuing)"
        fi
    fi
fi

print_success "MySQL Server ready: $MYSQL_HOST"

# -----------------------------------------------------------------------------
# Verify and retrieve PostgreSQL details (still part of step 6)
# -----------------------------------------------------------------------------
print_info "Retrieving PostgreSQL details..."

POSTGRES_HOST=$(az postgres flexible-server show \
    --name "$POSTGRES_SERVER" \
    --resource-group "$RESOURCE_GROUP" \
    --query fullyQualifiedDomainName -o tsv 2>/dev/null)

if [ -z "$POSTGRES_HOST" ]; then
    print_error "PostgreSQL creation failed. Check /tmp/postgres_error.log"
    cat /tmp/postgres_error.log
    exit 1
fi

# Configure PostgreSQL firewall rules
print_info "Configuring PostgreSQL firewall rules..."
if az postgres flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$POSTGRES_SERVER" \
    --rule-name "AllowAllAzureServices" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none 2>/dev/null; then
    print_success "PostgreSQL firewall rule created: AllowAllAzureServices"
else
    print_warning "PostgreSQL firewall rule may already exist (continuing)"
fi

# For dev/staging environments, allow deployer's IP for seeding and debugging
if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "staging" ]]; then
    # Reuse MY_IP from MySQL section if already fetched
    if [ -z "$MY_IP" ]; then
        MY_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")
    fi
    if [ -n "$MY_IP" ]; then
        print_info "Adding PostgreSQL firewall rule for deployer IP: $MY_IP"
        if az postgres flexible-server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$POSTGRES_SERVER" \
            --rule-name "AllowDeployerIP" \
            --start-ip-address "$MY_IP" \
            --end-ip-address "$MY_IP" \
            --output none 2>/dev/null; then
            print_success "PostgreSQL firewall rule created: AllowDeployerIP ($MY_IP)"
        else
            print_warning "Could not add deployer IP rule for PostgreSQL (continuing)"
        fi
    fi
fi

print_success "PostgreSQL Server ready: $POSTGRES_HOST"

# -----------------------------------------------------------------------------
# Verify and retrieve SQL Server details (still part of step 6)
# -----------------------------------------------------------------------------
print_info "Retrieving SQL Server details..."

SQL_HOST=$(az sql server show \
    --name "$SQL_SERVER" \
    --resource-group "$RESOURCE_GROUP" \
    --query fullyQualifiedDomainName -o tsv 2>/dev/null)

if [ -z "$SQL_HOST" ]; then
    print_error "SQL Server creation failed. Check /tmp/sql_error.log"
    cat /tmp/sql_error.log
    exit 1
fi

# Configure SQL Server firewall rules
print_info "Configuring SQL Server firewall rules..."
if az sql server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER" \
    --name "AllowAllAzureServices" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none 2>/dev/null; then
    print_success "SQL Server firewall rule created: AllowAllAzureServices"
else
    print_warning "SQL Server firewall rule may already exist (continuing)"
fi

# For dev/staging environments, allow deployer's IP for seeding and debugging
if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "staging" ]]; then
    # Reuse MY_IP from MySQL section if already fetched
    if [ -z "$MY_IP" ]; then
        MY_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")
    fi
    if [ -n "$MY_IP" ]; then
        print_info "Adding SQL Server firewall rule for deployer IP: $MY_IP"
        if az sql server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" \
            --server "$SQL_SERVER" \
            --name "AllowDeployerIP" \
            --start-ip-address "$MY_IP" \
            --end-ip-address "$MY_IP" \
            --output none 2>/dev/null; then
            print_success "SQL Server firewall rule created: AllowDeployerIP ($MY_IP)"
        else
            print_warning "Could not add deployer IP rule for SQL Server (continuing)"
        fi
    fi
fi

print_success "SQL Server ready: $SQL_HOST"

# Create order_service_db database
print_info "Creating SQL database: order_service_db..."
if az sql db create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER" \
    --name "order_service_db" \
    --edition Basic \
    --capacity 5 \
    --max-size 2GB \
    --output none 2>/dev/null; then
    print_success "SQL database created: order_service_db"
else
    print_warning "SQL database may already exist (continuing)"
fi

# Grant managed identity access to SQL Server
# This allows the container apps to use Azure AD authentication
print_info "Configuring managed identity SQL Server access..."
MANAGED_IDENTITY_OBJECT_ID=$(az identity show \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv 2>/dev/null || echo "")

if [ -n "$MANAGED_IDENTITY_OBJECT_ID" ]; then
    # Add managed identity as SQL Server admin (in addition to current user)
    # This allows automated deployments to work without manual SQL configuration
    MANAGED_IDENTITY_NAME="$MANAGED_IDENTITY"
    
    # Get the managed identity's client ID for SQL
    MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
        --name "$MANAGED_IDENTITY" \
        --resource-group "$RESOURCE_GROUP" \
        --query clientId -o tsv 2>/dev/null || echo "")
    
    if [ -n "$MANAGED_IDENTITY_CLIENT_ID" ]; then
        # Add managed identity as Azure AD admin for SQL Server
        # Note: This replaces the current admin. For multi-admin, use Azure AD groups
        print_info "Setting managed identity as additional SQL admin..."
        
        # Create an Azure AD group for SQL admins if needed (for multi-admin support)
        # For now, we'll use sqlcmd to grant database-level permissions
        
        # Use Access Token to run SQL commands
        print_info "Granting managed identity database permissions..."
        ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null || echo "")
        
        if [ -n "$ACCESS_TOKEN" ] && command -v sqlcmd &> /dev/null; then
            # Create SQL script
            SQL_SCRIPT=$(cat <<EOF
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$MANAGED_IDENTITY_NAME')
BEGIN
    CREATE USER [$MANAGED_IDENTITY_NAME] FROM EXTERNAL PROVIDER;
    PRINT 'Created user: $MANAGED_IDENTITY_NAME';
END
ELSE
BEGIN
    PRINT 'User already exists: $MANAGED_IDENTITY_NAME';
END

ALTER ROLE db_datareader ADD MEMBER [$MANAGED_IDENTITY_NAME];
ALTER ROLE db_datawriter ADD MEMBER [$MANAGED_IDENTITY_NAME];
ALTER ROLE db_ddladmin ADD MEMBER [$MANAGED_IDENTITY_NAME];
PRINT 'Granted permissions to: $MANAGED_IDENTITY_NAME';
EOF
)
            # Run SQL commands using Azure AD authentication
            echo "$SQL_SCRIPT" | sqlcmd -S "$SQL_HOST" -d "order_service_db" -G -I 2>/dev/null
            if [ $? -eq 0 ]; then
                print_success "Granted SQL permissions to managed identity: $MANAGED_IDENTITY_NAME"
            else
                print_warning "Could not grant SQL permissions automatically"
                print_info "Run manually in Azure Portal Query Editor:"
                print_info "  CREATE USER [$MANAGED_IDENTITY_NAME] FROM EXTERNAL PROVIDER;"
                print_info "  ALTER ROLE db_datareader ADD MEMBER [$MANAGED_IDENTITY_NAME];"
                print_info "  ALTER ROLE db_datawriter ADD MEMBER [$MANAGED_IDENTITY_NAME];"
                print_info "  ALTER ROLE db_ddladmin ADD MEMBER [$MANAGED_IDENTITY_NAME];"
            fi
        else
            print_warning "sqlcmd not available or token failed - manual SQL configuration required"
            print_info "Run in Azure Portal Query Editor (order_service_db):"
            print_info "  CREATE USER [$MANAGED_IDENTITY_NAME] FROM EXTERNAL PROVIDER;"
            print_info "  ALTER ROLE db_datareader ADD MEMBER [$MANAGED_IDENTITY_NAME];"
            print_info "  ALTER ROLE db_datawriter ADD MEMBER [$MANAGED_IDENTITY_NAME];"
            print_info "  ALTER ROLE db_ddladmin ADD MEMBER [$MANAGED_IDENTITY_NAME];"
        fi
    fi
else
    print_warning "Managed identity not found - SQL permissions must be configured manually"
fi

# =============================================================================
# 7. Create Azure Key Vault
# =============================================================================
print_step "Creating Key Vault"
if az keyvault create \
    --name "$KEY_VAULT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --enable-rbac-authorization true \
    --public-network-access Enabled \
    --output none 2>&1; then
    print_success "Key Vault created: $KEY_VAULT"
else
    print_error "Failed to create Key Vault: $KEY_VAULT"
    exit 1
fi

# Configure Key Vault network rules - allow public access and Azure services
# Note: Public access is needed for CLI access during deployment and local development
# In production, consider restricting to specific IPs or VNet
print_info "Configuring Key Vault network access..."
if az keyvault update \
    --name "$KEY_VAULT" \
    --resource-group "$RESOURCE_GROUP" \
    --public-network-access Enabled \
    --default-action Allow \
    --bypass AzureServices \
    --output none 2>/dev/null; then
    print_success "Key Vault network rules configured (public access enabled)"
else
    print_warning "Key Vault network rules may already be configured (continuing)"
fi

# Grant managed identity access to Key Vault using REST API
# Note: Using REST API due to Azure CLI 'az role assignment create' bug with MissingSubscription error
print_info "Granting managed identity Key Vault access..."
KV_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT"
if create_role_assignment "$IDENTITY_PRINCIPAL_ID" "Key Vault Secrets User" "$KV_SCOPE" "ServicePrincipal"; then
    print_success "Key Vault role assignment created"
else
    print_warning "Key Vault role assignment may already exist (continuing)"
fi

KEY_VAULT_URL="https://${KEY_VAULT}.vault.azure.net/"
print_info "Key Vault URL: $KEY_VAULT_URL"

# -----------------------------------------------------------------------------
# 8. Store Secrets in Key Vault
# -----------------------------------------------------------------------------
print_step "Storing Secrets in Key Vault"

# Get current user's object ID for Key Vault access
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

if [ -n "$CURRENT_USER_ID" ]; then
    # Grant current user access to set secrets using REST API
    # Note: Using REST API due to Azure CLI 'az role assignment create' bug with MissingSubscription error
    print_info "Granting current user Key Vault Secrets Officer role..."
    KV_USER_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT"
    if create_role_assignment "$CURRENT_USER_ID" "Key Vault Secrets Officer" "$KV_USER_SCOPE" "User"; then
        print_success "Role assignment created"
    else
        print_warning "Role assignment may already exist (continuing)"
    fi
    
    # Wait for role assignment to propagate
    print_info "Waiting for role assignment to propagate (15s)..."
    sleep 15

    # Store secrets
    print_info "Storing secrets in Key Vault..."
    SECRET_COUNT=0
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "service-bus-connection" --value "$SERVICE_BUS_CONNECTION" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: service-bus-connection"
    else
        print_warning "Failed to store: service-bus-connection"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "redis-password" --value "$REDIS_KEY" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: redis-password"
    else
        print_warning "Failed to store: redis-password"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "cosmos-connection" --value "$COSMOS_CONNECTION" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: cosmos-connection"
    else
        print_warning "Failed to store: cosmos-connection"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "mysql-password" --value "$MYSQL_ADMIN_PASSWORD" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: mysql-password"
    else
        print_warning "Failed to store: mysql-password"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "mysql-connection" --value "Server=$MYSQL_HOST;Database=order_db;User=$MYSQL_ADMIN_USER;Password=$MYSQL_ADMIN_PASSWORD;SslMode=Required" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: mysql-connection"
    else
        print_warning "Failed to store: mysql-connection"
    fi
    
    # PostgreSQL secrets (for order-processor-service)
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "postgres-password" --value "$POSTGRES_ADMIN_PASSWORD" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: postgres-password"
    else
        print_warning "Failed to store: postgres-password"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "postgres-connection" --value "jdbc:postgresql://$POSTGRES_HOST:5432/order_processor_db?sslmode=require&user=$POSTGRES_ADMIN_USER&password=$POSTGRES_ADMIN_PASSWORD" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: postgres-connection"
    else
        print_warning "Failed to store: postgres-connection"
    fi
    
    # Store PostgreSQL configuration for Dapr secret store (nested keys)
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "database-host" --value "$POSTGRES_HOST" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: database-host (PostgreSQL)"
    else
        print_warning "Failed to store: database-host"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "database-port" --value "5432" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: database-port"
    else
        print_warning "Failed to store: database-port"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "database-name" --value "order_processor_db" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: database-name"
    else
        print_warning "Failed to store: database-name"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "database-user" --value "$POSTGRES_ADMIN_USER" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: database-user"
    else
        print_warning "Failed to store: database-user"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "database-password" --value "$POSTGRES_ADMIN_PASSWORD" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: database-password"
    else
        print_warning "Failed to store: database-password"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "appinsights-connection-string" --value "$APP_INSIGHTS_CONNECTION_STRING" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: appinsights-connection-string"
    else
        print_warning "Failed to store: appinsights-connection-string"
    fi
    
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "appinsights-instrumentation-key" --value "$APP_INSIGHTS_INSTRUMENTATION_KEY" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: appinsights-instrumentation-key"
    else
        print_warning "Failed to store: appinsights-instrumentation-key"
    fi
    
    # SQL Server connection info (Azure AD authentication - no password)
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "sql-host" --value "$SQL_HOST" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: sql-host"
    else
        print_warning "Failed to store: sql-host"
    fi
    
    # SQL Server connection string for order-service (Azure AD Default auth for managed identity)
    if az keyvault secret set --vault-name "$KEY_VAULT" --name "sql-connection" --value "Server=$SQL_HOST;Database=order_service_db;Authentication=Active Directory Default;TrustServerCertificate=True;Encrypt=True" --output none 2>/dev/null; then
        SECRET_COUNT=$((SECRET_COUNT + 1))
        print_success "Stored: sql-connection"
    else
        print_warning "Failed to store: sql-connection"
    fi
    
    print_success "Stored $SECRET_COUNT/9 secrets in Key Vault"
else
    print_warning "Could not store secrets (run 'az login' with user account)"
fi

# -----------------------------------------------------------------------------
# 9. Configure Dapr Components
# -----------------------------------------------------------------------------
print_step "Configuring Dapr Components"

# Dapr Pub/Sub Component (Service Bus Topics)
print_info "Configuring pubsub component (Service Bus)..."
cat > /tmp/dapr-pubsub.yaml << PUBSUBEOF
componentType: pubsub.azure.servicebus.topics
version: v1
metadata:
  - name: connectionString
    value: "${SERVICE_BUS_CONNECTION}"
scopes:
  - user-service
  - auth-service
  - product-service
  - order-service
  - cart-service
  - inventory-service
  - payment-service
  - notification-service
  - audit-service
  - review-service
  - order-processor-service
PUBSUBEOF
if az containerapp env dapr-component set \
    --name "$CONTAINER_ENV" \
    --resource-group "$RESOURCE_GROUP" \
    --dapr-component-name "pubsub" \
    --yaml /tmp/dapr-pubsub.yaml \
    --output none 2>&1; then
    print_success "Dapr pubsub component configured"
else
    print_error "Failed to configure Dapr pubsub component"
fi

# Dapr State Store Component (Redis)
print_info "Configuring statestore component (Redis)..."
cat > /tmp/dapr-statestore.yaml << STATEEOF
componentType: state.redis
version: v1
metadata:
  - name: redisHost
    value: "${REDIS_HOST}:${REDIS_PORT}"
  - name: redisPassword
    value: "${REDIS_KEY}"
  - name: enableTLS
    value: "true"
scopes:
  - cart-service
  - order-service
  - user-service
  - auth-service
STATEEOF
if az containerapp env dapr-component set \
    --name "$CONTAINER_ENV" \
    --resource-group "$RESOURCE_GROUP" \
    --dapr-component-name "statestore" \
    --yaml /tmp/dapr-statestore.yaml \
    --output none 2>&1; then
    print_success "Dapr statestore component configured"
else
    print_error "Failed to configure Dapr statestore component"
fi

# Dapr Secret Store Component (Key Vault)
print_info "Configuring secretstore component (Key Vault)..."
cat > /tmp/dapr-secretstore.yaml << SECRETEOF
componentType: secretstores.azure.keyvault
version: v1
metadata:
  - name: vaultName
    value: "${KEY_VAULT}"
  - name: azureClientId
    value: "${IDENTITY_CLIENT_ID}"
SECRETEOF
if az containerapp env dapr-component set \
    --name "$CONTAINER_ENV" \
    --resource-group "$RESOURCE_GROUP" \
    --dapr-component-name "secretstore" \
    --yaml /tmp/dapr-secretstore.yaml \
    --output none 2>&1; then
    print_success "Dapr secretstore component configured"
else
    print_error "Failed to configure Dapr secretstore component"
fi

# Clean up temporary YAML files
rm -f /tmp/dapr-pubsub.yaml /tmp/dapr-statestore.yaml /tmp/dapr-secretstore.yaml

# Calculate total time
TOTAL_TIME=$((SECONDS - SCRIPT_START_TIME))
TOTAL_MINUTES=$((TOTAL_TIME / 60))
TOTAL_SECONDS=$((TOTAL_TIME % 60))

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}   ✅ INFRASTRUCTURE DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}   ⏱️  Total time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""
echo -e "${CYAN}📋 Deployment Configuration:${NC}"
echo -e "   Environment:            ${YELLOW}$ENVIRONMENT${NC}"
echo -e "   Location:               ${YELLOW}$LOCATION${NC}"
echo -e "   Suffix:                 ${YELLOW}$SUFFIX${NC}"
echo ""
echo -e "${CYAN}📋 Resource Summary:${NC}"
echo -e "   Resource Group:         ${YELLOW}$RESOURCE_GROUP${NC}"
echo -e "   Container Registry:     ${YELLOW}$ACR_LOGIN_SERVER${NC}"
echo -e "   Container Apps Env:     ${YELLOW}$CONTAINER_ENV${NC}"
echo -e "   Application Insights:   ${YELLOW}$APP_INSIGHTS${NC}"
echo -e "   Service Bus:            ${YELLOW}$SERVICE_BUS.servicebus.windows.net${NC}"
echo -e "   Redis Cache:            ${YELLOW}$REDIS_HOST${NC}"
echo -e "   Cosmos DB:              ${YELLOW}$COSMOS_ACCOUNT.mongo.cosmos.azure.com${NC}"
echo -e "   MySQL Server:           ${YELLOW}$MYSQL_HOST${NC}"
echo -e "   SQL Server:             ${YELLOW}$SQL_HOST${NC}"
echo -e "   Key Vault:              ${YELLOW}$KEY_VAULT_URL${NC}"
echo -e "   Managed Identity:       ${YELLOW}$MANAGED_IDENTITY${NC}"
echo ""
echo -e "${RED}🔐 Credentials (save securely!):${NC}"
echo -e "   MySQL Admin User:       ${YELLOW}$MYSQL_ADMIN_USER${NC}"
echo -e "   MySQL Admin Password:   ${YELLOW}$MYSQL_ADMIN_PASSWORD${NC}"
echo -e "   SQL Server Auth:        ${YELLOW}Azure AD-only (use managed identity)${NC}"
echo ""
echo -e "${CYAN}📝 Environment Variables for Services:${NC}"
echo -e "   ${BLUE}export RESOURCE_GROUP=\"$RESOURCE_GROUP\"${NC}"
echo -e "   ${BLUE}export ACR_NAME=\"$ACR_NAME\"${NC}"
echo -e "   ${BLUE}export ACR_LOGIN_SERVER=\"$ACR_LOGIN_SERVER\"${NC}"
echo -e "   ${BLUE}export CONTAINER_ENV=\"$CONTAINER_ENV\"${NC}"
echo -e "   ${BLUE}export MANAGED_IDENTITY_ID=\"$IDENTITY_ID\"${NC}"
echo -e "   ${BLUE}export APPLICATIONINSIGHTS_CONNECTION_STRING=\"$APP_INSIGHTS_CONNECTION_STRING\"${NC}"
echo -e "   ${BLUE}export SUFFIX=\"$SUFFIX\"${NC}"
echo ""
echo -e "${CYAN}🚀 Next Steps:${NC}"
echo -e "   1. Save the suffix '${YELLOW}$SUFFIX${NC}' - you'll need it for service deployments"
echo -e "   2. Deploy individual services using their scripts/aca.sh"
echo -e "   3. Configure DNS and custom domains"
echo -e "   4. Set up monitoring and alerts"
echo ""
echo -e "${CYAN}💡 To deploy a service:${NC}"
echo -e "   ${BLUE}cd ../../../<service-name>/scripts${NC}"
echo -e "   ${BLUE}./aca.sh $ENVIRONMENT${NC}"
echo ""
echo -e "${YELLOW}💾 Important: The suffix '$SUFFIX' is stored as a tag on the resource group.${NC}"
echo -e "   To retrieve it later: ${BLUE}az group show -n $RESOURCE_GROUP --query \"tags.suffix\" -o tsv${NC}"
echo ""
