#!/bin/bash

# =============================================================================
# xshopai Infrastructure Deployment Orchestrator
# =============================================================================
# This is the main entry point for deploying xshopai infrastructure to Azure.
# It orchestrates the deployment of all resources in the correct order.
#
# Architecture:
#   - Modular design: Each resource has its own deployment module
#   - Easy debugging: Run individual modules to troubleshoot specific resources
#   - Parallel execution: Long-running resources are deployed in parallel
#
# Usage:
#   ./deploy.sh [environment] [subscription] [location] [suffix]
#
# Examples:
#   ./deploy.sh                                    # Interactive mode
#   ./deploy.sh dev                                # Dev environment, interactive
#   ./deploy.sh dev "My Subscription" swedencentral abc1   # Full non-interactive
#
# To deploy a single resource (for debugging):
#   source modules/common.sh
#   export RESOURCE_GROUP="rg-xshopai-dev-abc1" ...
#   ./modules/12-keyvault.sh
# =============================================================================

set -e

# Get script directory (for sourcing modules)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source common utilities
source "$MODULES_DIR/common.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ENVIRONMENT="${1:-}"
SUBSCRIPTION="${2:-}"
LOCATION="${3:-}"
SUFFIX="${4:-}"
PROJECT_NAME="xshopai"

# Track deployment progress
TOTAL_STEPS=11
CURRENT_STEP=0
SCRIPT_START_TIME=0

# Log file for detailed debugging
LOG_FILE="/tmp/xshopai-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

print_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local ELAPSED=0
    if [ $SCRIPT_START_TIME -gt 0 ]; then
        ELAPSED=$((SECONDS - SCRIPT_START_TIME))
    fi
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[$CURRENT_STEP/$TOTAL_STEPS] $1${NC} ${CYAN}(${ELAPSED}s elapsed)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Debug logging function
log_debug() {
    echo -e "${CYAN}[DEBUG $(date +%H:%M:%S)] $1${NC}"
}

# =============================================================================
# Prerequisites Check
# =============================================================================
print_header "xshopai Infrastructure Deployment"

echo -e "${CYAN}Log file: $LOG_FILE${NC}"
echo ""

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
log_debug "Azure CLI version: $(az version --query '"azure-cli"' -o tsv)"
print_success "Azure CLI is installed"

# Check if logged into Azure
if ! az account show &> /dev/null; then
    print_warning "Not logged into Azure. Initiating login..."
    az login
fi
log_debug "Logged in as: $(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo 'Service Principal')"
print_success "Logged into Azure"

# Check openssl
if ! command -v openssl &> /dev/null; then
    print_warning "openssl not found - will use fallback for random generation"
else
    log_debug "openssl version: $(openssl version)"
fi

# Install required CLI extensions
print_info "Installing required CLI extensions..."
az extension add --name communication --yes 2>/dev/null || true
log_debug "Installed communication extension"
print_success "CLI extensions ready"

# Register required resource providers
print_info "Registering required resource providers..."
log_debug "Registering Microsoft.Sql..."
az provider register --namespace Microsoft.Sql --wait 2>/dev/null || true
log_debug "Registering Microsoft.App..."
az provider register --namespace Microsoft.App --wait 2>/dev/null || true
log_debug "Registering Microsoft.ContainerRegistry..."
az provider register --namespace Microsoft.ContainerRegistry --wait 2>/dev/null || true
log_debug "Registering Microsoft.ServiceBus..."
az provider register --namespace Microsoft.ServiceBus --wait 2>/dev/null || true
log_debug "Registering Microsoft.Cache..."
az provider register --namespace Microsoft.Cache --wait 2>/dev/null || true
log_debug "Registering Microsoft.DocumentDB..."
az provider register --namespace Microsoft.DocumentDB --wait 2>/dev/null || true
log_debug "Registering Microsoft.DBforMySQL..."
az provider register --namespace Microsoft.DBforMySQL --wait 2>/dev/null || true
log_debug "Registering Microsoft.DBforPostgreSQL..."
az provider register --namespace Microsoft.DBforPostgreSQL --wait 2>/dev/null || true
log_debug "Registering Microsoft.Communication..."
az provider register --namespace Microsoft.Communication --wait 2>/dev/null || true
log_debug "Registering Microsoft.KeyVault..."
az provider register --namespace Microsoft.KeyVault --wait 2>/dev/null || true
print_success "Resource providers registered"

# =============================================================================
# Environment Selection
# =============================================================================
print_header "Environment Configuration"

if [ -z "$ENVIRONMENT" ]; then
    echo -e "${CYAN}Available Environments:${NC}"
    echo "   dev  - Development environment"
    echo "   prod - Production environment"
    echo ""
    read -p "Enter environment (dev/prod) [dev]: " ENVIRONMENT
    ENVIRONMENT="${ENVIRONMENT:-dev}"
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT (valid: dev, prod)"
    exit 1
fi
print_success "Environment: $ENVIRONMENT"

# =============================================================================
# Subscription Selection
# =============================================================================
print_header "Azure Subscription"

echo -e "${CYAN}Available Subscriptions:${NC}"
az account list --query "[].{Name:name, SubscriptionId:id, IsDefault:isDefault}" --output table
echo ""

if [ -z "$SUBSCRIPTION" ]; then
    read -p "Enter Subscription ID (leave empty for default): " SUBSCRIPTION
fi

if [ -n "$SUBSCRIPTION" ]; then
    az account set --subscription "$SUBSCRIPTION"
fi

export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
print_success "Using subscription: $SUBSCRIPTION_NAME"

# =============================================================================
# Location Selection
# =============================================================================
print_header "Azure Location"

echo -e "${CYAN}Common Locations:${NC}"
echo "   swedencentral, westeurope, northeurope, eastus, westus2"
echo ""

if [ -z "$LOCATION" ]; then
    read -p "Enter location [swedencentral]: " LOCATION
    LOCATION="${LOCATION:-swedencentral}"
fi

if ! az account list-locations --query "[?name=='$LOCATION'].name" -o tsv | grep -q "$LOCATION"; then
    print_error "Invalid location: $LOCATION"
    exit 1
fi
export LOCATION
print_success "Location: $LOCATION"

# =============================================================================
# Suffix Configuration
# =============================================================================
print_header "Unique Suffix"

DEFAULT_SUFFIX=$(openssl rand -hex 2 2>/dev/null || date +%s | tail -c 5)

if [ -z "$SUFFIX" ]; then
    read -p "Enter unique suffix (3-6 alphanumeric) [$DEFAULT_SUFFIX]: " SUFFIX
    SUFFIX="${SUFFIX:-$DEFAULT_SUFFIX}"
fi

if [[ ! "$SUFFIX" =~ ^[a-z0-9]{3,6}$ ]]; then
    print_error "Invalid suffix: $SUFFIX (must be 3-6 lowercase alphanumeric)"
    exit 1
fi
export SUFFIX
print_success "Suffix: $SUFFIX"

# =============================================================================
# Generate Resource Names
# =============================================================================
generate_resource_names "$PROJECT_NAME" "$ENVIRONMENT" "$SUFFIX"

# =============================================================================
# Deployment Confirmation
# =============================================================================
print_header "Deployment Summary"

echo -e "${CYAN}Configuration:${NC}"
echo "   Environment:   $ENVIRONMENT"
echo "   Subscription:  $SUBSCRIPTION_NAME"
echo "   Location:      $LOCATION"
echo "   Suffix:        $SUFFIX"
echo ""
echo -e "${CYAN}Resources to be created:${NC}"
echo "   Resource Group:        $RESOURCE_GROUP"
echo "   Managed Identity:      $MANAGED_IDENTITY"
echo "   Container Registry:    $ACR_NAME"
echo "   Log Analytics:         $LOG_ANALYTICS"
echo "   Application Insights:  $APP_INSIGHTS"
echo "   Container Apps Env:    $CONTAINER_ENV"
echo "   Service Bus:           $SERVICE_BUS"
echo "   Redis Cache:           $REDIS_NAME"
echo "   Cosmos DB:             $COSMOS_ACCOUNT"
echo "   MySQL Server:          $MYSQL_SERVER"
echo "   SQL Server:            $SQL_SERVER"
echo "   PostgreSQL Server:     $POSTGRES_SERVER"
echo "   Communication Service: $COMMUNICATION_SERVICE"
echo "   Key Vault:             $KEY_VAULT"
echo ""

read -p "Proceed with deployment? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    print_error "Deployment cancelled."
    exit 1
fi

SCRIPT_START_TIME=$SECONDS

# =============================================================================
# DEPLOYMENT EXECUTION
# =============================================================================

# -----------------------------------------------------------------------------
# Step 1: Resource Group
# -----------------------------------------------------------------------------
print_progress "Creating Resource Group"
source "$MODULES_DIR/01-resource-group.sh"
deploy_resource_group || { print_error "Resource Group deployment failed"; exit 1; }

# -----------------------------------------------------------------------------
# Step 2: Managed Identity
# -----------------------------------------------------------------------------
print_progress "Creating Managed Identity"
log_debug "Loading Managed Identity module..."
source "$MODULES_DIR/02-managed-identity.sh"
log_debug "Deploying Managed Identity: $MANAGED_IDENTITY"
deploy_managed_identity || { print_error "Managed Identity deployment failed"; exit 1; }

# Capture Identity properties for later use (module exports them, but re-fetch to be safe)
export IDENTITY_CLIENT_ID=$(az identity show \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --query clientId -o tsv 2>/dev/null || echo "")
export IDENTITY_PRINCIPAL_ID=$(az identity show \
    --name "$MANAGED_IDENTITY" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv 2>/dev/null || echo "")
log_debug "Managed Identity Client ID: $IDENTITY_CLIENT_ID"
log_debug "Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID"

# -----------------------------------------------------------------------------
# Step 3: ACR + Monitoring (parallel-capable but run sequentially for stability)
# -----------------------------------------------------------------------------
print_progress "Creating ACR & Monitoring"
log_debug "Loading ACR and Monitoring modules..."
source "$MODULES_DIR/03-acr.sh"
source "$MODULES_DIR/04-monitoring.sh"

log_debug "Deploying ACR: $ACR_NAME"
deploy_acr || { print_error "ACR deployment failed"; exit 1; }
log_debug "ACR deployed successfully"

log_debug "Deploying Monitoring (Log Analytics: $LOG_ANALYTICS, App Insights: $APP_INSIGHTS)"
deploy_monitoring || { print_error "Monitoring deployment failed"; exit 1; }
log_debug "Monitoring deployed successfully"

# -----------------------------------------------------------------------------
# Step 4: Container Apps Environment
# -----------------------------------------------------------------------------
print_progress "Creating Container Apps Environment"
log_debug "Loading Container Apps Environment module..."
source "$MODULES_DIR/05-container-apps-env.sh"
log_debug "Deploying Container Apps Environment: $CONTAINER_ENV"
deploy_container_apps_env || { print_error "Container Apps Environment deployment failed"; exit 1; }
log_debug "Container Apps Environment deployed successfully"

# -----------------------------------------------------------------------------
# Step 5: Service Bus
# -----------------------------------------------------------------------------
print_progress "Creating Service Bus"
log_debug "Loading Service Bus module..."
source "$MODULES_DIR/06-service-bus.sh"
log_debug "Deploying Service Bus: $SERVICE_BUS"
deploy_service_bus || { print_error "Service Bus deployment failed"; exit 1; }
log_debug "Service Bus deployed successfully"

# -----------------------------------------------------------------------------
# Step 6: Data Resources (Parallel) - These take the longest
# -----------------------------------------------------------------------------
print_progress "Creating Data Resources (Redis, Cosmos DB, MySQL, SQL, PostgreSQL)"
print_warning "Starting parallel deployment of data resources..."
print_info "This will take 10-15 minutes total"
log_debug "Starting parallel deployment at $(date)"

source "$MODULES_DIR/07-redis.sh"
source "$MODULES_DIR/08-cosmos-db.sh"
source "$MODULES_DIR/09-mysql.sh"
source "$MODULES_DIR/10-sql-server.sh"
source "$MODULES_DIR/11-postgresql.sh"

# Fixed database credentials (same password used for creation AND Key Vault)
# These are deterministic so re-running the script won't cause password mismatch
export MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-xshopaiadmin}"
export MYSQL_ADMIN_PASSWORD="${MYSQL_ADMIN_PASSWORD:-xshopaipassword123}"
export POSTGRES_ADMIN_USER="${POSTGRES_ADMIN_USER:-pgadmin}"
export POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-xshopaipassword123}"

log_debug "MySQL credentials: user=$MYSQL_ADMIN_USER"
log_debug "PostgreSQL credentials: user=$POSTGRES_ADMIN_USER"

# Run data resources in parallel with logging
log_debug "Starting Redis deployment..."
deploy_redis > /tmp/redis_deploy.log 2>&1 &
REDIS_PID=$!

log_debug "Starting Cosmos DB deployment..."
deploy_cosmos_db > /tmp/cosmos_deploy.log 2>&1 &
COSMOS_PID=$!

log_debug "Starting MySQL deployment..."
deploy_mysql > /tmp/mysql_deploy.log 2>&1 &
MYSQL_PID=$!

log_debug "Starting SQL Server deployment..."
deploy_sql_server > /tmp/sql_deploy.log 2>&1 &
SQL_PID=$!

log_debug "Starting PostgreSQL deployment..."
deploy_postgresql > /tmp/postgres_deploy.log 2>&1 &
POSTGRES_PID=$!

# Wait for all parallel jobs with status monitoring
print_info "Waiting for all data resources to complete..."

PARALLEL_START=$SECONDS
while true; do
    REDIS_DONE=true; COSMOS_DONE=true; MYSQL_DONE=true; SQL_DONE=true; POSTGRES_DONE=true
    
    kill -0 $REDIS_PID 2>/dev/null && REDIS_DONE=false
    kill -0 $COSMOS_PID 2>/dev/null && COSMOS_DONE=false
    kill -0 $MYSQL_PID 2>/dev/null && MYSQL_DONE=false
    kill -0 $SQL_PID 2>/dev/null && SQL_DONE=false
    kill -0 $POSTGRES_PID 2>/dev/null && POSTGRES_DONE=false
    
    ELAPSED=$((SECONDS - PARALLEL_START))
    printf "\r   ⏱️  %3ds | Redis: %s | Cosmos: %s | MySQL: %s | SQL: %s | Postgres: %s   " \
        "$ELAPSED" \
        "$($REDIS_DONE && echo '✅' || echo '⏳')" \
        "$($COSMOS_DONE && echo '✅' || echo '⏳')" \
        "$($MYSQL_DONE && echo '✅' || echo '⏳')" \
        "$($SQL_DONE && echo '✅' || echo '⏳')" \
        "$($POSTGRES_DONE && echo '✅' || echo '⏳')"
    
    $REDIS_DONE && $COSMOS_DONE && $MYSQL_DONE && $SQL_DONE && $POSTGRES_DONE && break
    sleep 5
done
echo ""

# Check exit codes
FAILED=0
wait $REDIS_PID || { print_error "Redis deployment failed - check /tmp/redis_deploy.log"; cat /tmp/redis_deploy.log; FAILED=1; }
wait $COSMOS_PID || { print_error "Cosmos DB deployment failed - check /tmp/cosmos_deploy.log"; cat /tmp/cosmos_deploy.log; FAILED=1; }
wait $MYSQL_PID || { print_error "MySQL deployment failed - check /tmp/mysql_deploy.log"; cat /tmp/mysql_deploy.log; FAILED=1; }
wait $SQL_PID || { print_error "SQL Server deployment failed - check /tmp/sql_deploy.log"; cat /tmp/sql_deploy.log; FAILED=1; }
wait $POSTGRES_PID || { print_error "PostgreSQL deployment failed - check /tmp/postgres_deploy.log"; cat /tmp/postgres_deploy.log; FAILED=1; }

if [ $FAILED -eq 1 ]; then
    print_error "One or more data resources failed to deploy"
    print_info "Check log files in /tmp/ for details"
    exit 1
fi

log_debug "All parallel deployments completed"
print_success "All data resources deployed"

# Re-retrieve resource properties (exports lost in subshells)
print_info "Retrieving resource connection strings..."

# Redis
log_debug "Retrieving Redis properties..."
export REDIS_HOST=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query hostName -o tsv 2>/dev/null || echo "")
export REDIS_KEY=$(az redis list-keys --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query primaryKey -o tsv 2>/dev/null || echo "")
export REDIS_PORT=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query sslPort -o tsv 2>/dev/null || echo "6380")
if [ -z "$REDIS_HOST" ]; then
    print_error "Failed to retrieve Redis host"
    exit 1
fi
log_debug "Redis host: $REDIS_HOST:$REDIS_PORT"
print_success "Redis: $REDIS_HOST"

# Cosmos DB
log_debug "Retrieving Cosmos DB properties..."
export COSMOS_CONNECTION=$(az cosmosdb keys list --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --type connection-strings --query "connectionStrings[?keyKind=='Primary' && type=='MongoDB'].connectionString | [0]" -o tsv 2>/dev/null || echo "")
if [ -z "$COSMOS_CONNECTION" ]; then
    # Try alternative query
    export COSMOS_CONNECTION=$(az cosmosdb keys list --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --type connection-strings --query "connectionStrings[0].connectionString" -o tsv 2>/dev/null || echo "")
fi
if [ -z "$COSMOS_CONNECTION" ]; then
    print_error "Failed to retrieve Cosmos DB connection string"
    exit 1
fi
log_debug "Cosmos DB connection retrieved (length: ${#COSMOS_CONNECTION})"
print_success "Cosmos DB: $COSMOS_ACCOUNT.mongo.cosmos.azure.com"

# MySQL
log_debug "Retrieving MySQL properties..."
export MYSQL_HOST=$(az mysql flexible-server show --name "$MYSQL_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv 2>/dev/null || echo "")
if [ -z "$MYSQL_HOST" ]; then
    print_error "Failed to retrieve MySQL host"
    exit 1
fi
# Azure MySQL requires SSL - include certificate path (installed in container images)
export MYSQL_SERVER_CONNECTION="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306?ssl_ca=/etc/ssl/certs/DigiCertGlobalRootG2.crt.pem"
log_debug "MySQL host: $MYSQL_HOST"
print_success "MySQL: $MYSQL_HOST"

# Configure MySQL firewall
log_debug "Configuring MySQL firewall rules..."
az mysql flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MYSQL_SERVER" \
    --rule-name "AllowAllAzureServices" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none 2>/dev/null || log_debug "MySQL firewall rule may already exist"

# SQL Server
log_debug "Retrieving SQL Server properties..."
export SQL_HOST=$(az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv 2>/dev/null || echo "")
if [ -z "$SQL_HOST" ]; then
    print_error "Failed to retrieve SQL Server host"
    exit 1
fi
export SQL_SERVER_CONNECTION="Server=$SQL_HOST;Authentication=Active Directory Default;TrustServerCertificate=True;Encrypt=True"
log_debug "SQL Server host: $SQL_HOST"
print_success "SQL Server: $SQL_HOST"

# PostgreSQL
log_debug "Retrieving PostgreSQL properties..."
export POSTGRES_HOST=$(az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv 2>/dev/null || echo "")
if [ -z "$POSTGRES_HOST" ]; then
    print_error "Failed to retrieve PostgreSQL host"
    exit 1
fi
export POSTGRES_SERVER_CONNECTION="jdbc:postgresql://${POSTGRES_HOST}:5432/?sslmode=require&user=${POSTGRES_ADMIN_USER}&password=${POSTGRES_ADMIN_PASSWORD}"
log_debug "PostgreSQL host: $POSTGRES_HOST"
print_success "PostgreSQL: $POSTGRES_HOST"

# Configure PostgreSQL firewall
log_debug "Configuring PostgreSQL firewall rules..."
az postgres flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$POSTGRES_SERVER" \
    --rule-name "AllowAllAzureServices" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none 2>/dev/null || log_debug "PostgreSQL firewall rule may already exist"

# For dev environment, add deployer's IP
if [[ "$ENVIRONMENT" == "dev" ]]; then
    MY_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$MY_IP" ]; then
        log_debug "Adding deployer IP $MY_IP to firewall rules..."
        az mysql flexible-server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" --name "$MYSQL_SERVER" \
            --rule-name "AllowDeployerIP" --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" \
            --output none 2>/dev/null || true
        az postgres flexible-server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" --name "$POSTGRES_SERVER" \
            --rule-name "AllowDeployerIP" --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" \
            --output none 2>/dev/null || true
        az sql server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER" \
            --name "AllowDeployerIP" --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" \
            --output none 2>/dev/null || true
        print_info "Added deployer IP ($MY_IP) to MySQL, PostgreSQL, and SQL Server firewall rules"
    fi
fi

# -----------------------------------------------------------------------------
# Step 7: Azure Communication Services (Email)
# -----------------------------------------------------------------------------
print_progress "Creating Azure Communication Services"
log_debug "Loading Communication Services module..."
source "$MODULES_DIR/14-communication-service.sh"

# Set data location for Communication Services (must be UnitedStates or Europe)
export DATA_LOCATION="UnitedStates"
log_debug "Deploying Communication Services: $COMMUNICATION_SERVICE with data location: $DATA_LOCATION"
deploy_communication_service || { print_error "Communication Services deployment failed"; exit 1; }
log_debug "Communication Services deployed successfully"

# -----------------------------------------------------------------------------
# Step 8: Key Vault (needs connection strings from data resources + ACS)
# -----------------------------------------------------------------------------
print_progress "Creating Key Vault"
log_debug "Loading Key Vault module..."
source "$MODULES_DIR/12-keyvault.sh"
log_debug "Deploying Key Vault: $KEY_VAULT_NAME"
deploy_keyvault || { print_error "Key Vault deployment failed"; exit 1; }
log_debug "Key Vault deployed successfully: $KEY_VAULT_URL"

# -----------------------------------------------------------------------------
# Step 9: Store Secrets in Key Vault
# -----------------------------------------------------------------------------
print_progress "Storing Secrets in Key Vault"
log_debug "Preparing to store secrets..."
log_debug "Available connection strings:"
log_debug "  - Redis: ${REDIS_HOST:-MISSING}"
log_debug "  - Cosmos: ${COSMOS_CONNECTION:+SET (${#COSMOS_CONNECTION} chars)}"
log_debug "  - MySQL: ${MYSQL_HOST:-MISSING}"
log_debug "  - SQL: ${SQL_HOST:-MISSING}"
log_debug "  - PostgreSQL: ${POSTGRES_HOST:-MISSING}"

store_keyvault_secrets || { print_error "Secret storage failed"; exit 1; }
log_debug "All secrets stored in Key Vault"

# -----------------------------------------------------------------------------
# Step 10: Dapr Components
# -----------------------------------------------------------------------------
print_progress "Configuring Dapr Components"
log_debug "Loading Dapr components module..."
source "$MODULES_DIR/13-dapr-components.sh"

# Ensure IDENTITY_CLIENT_ID is set for Dapr components
if [ -z "$IDENTITY_CLIENT_ID" ]; then
    log_debug "Retrieving Managed Identity Client ID..."
    export IDENTITY_CLIENT_ID=$(az identity show \
        --name "$MANAGED_IDENTITY" \
        --resource-group "$RESOURCE_GROUP" \
        --query clientId -o tsv 2>/dev/null || echo "")
    if [ -z "$IDENTITY_CLIENT_ID" ]; then
        print_error "Failed to retrieve Managed Identity Client ID"
        exit 1
    fi
    log_debug "Managed Identity Client ID: $IDENTITY_CLIENT_ID"
fi

log_debug "Configuring Dapr components with:"
log_debug "  - Service Bus: $SERVICE_BUS"
log_debug "  - Key Vault: $KEY_VAULT_NAME"
log_debug "  - Redis Host: $REDIS_HOST:$REDIS_PORT"
log_debug "  - Identity Client ID: $IDENTITY_CLIENT_ID"

configure_dapr_components || { print_error "Dapr configuration failed"; exit 1; }
log_debug "Dapr components configured successfully"

# =============================================================================
# Deployment Complete
# =============================================================================
TOTAL_TIME=$((SECONDS - SCRIPT_START_TIME))
TOTAL_MINUTES=$((TOTAL_TIME / 60))
TOTAL_SECONDS=$((TOTAL_TIME % 60))

log_debug "Deployment completed at $(date)"
log_debug "Total deployment time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"

print_progress "Deployment Complete!"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   ✅ INFRASTRUCTURE DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}   ⏱️  Total time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}📋 Resource Summary:${NC}"
echo -e "   Resource Group:         ${YELLOW}$RESOURCE_GROUP${NC}"
echo -e "   Container Registry:     ${YELLOW}${ACR_NAME}.azurecr.io${NC}"
echo -e "   Container Apps Env:     ${YELLOW}$CONTAINER_ENV${NC}"
echo -e "   Application Insights:   ${YELLOW}$APP_INSIGHTS${NC}"
echo -e "   Service Bus:            ${YELLOW}$SERVICE_BUS.servicebus.windows.net${NC}"
echo -e "   Redis Cache:            ${YELLOW}$REDIS_HOST${NC}"
echo -e "   Cosmos DB:              ${YELLOW}$COSMOS_ACCOUNT.mongo.cosmos.azure.com${NC}"
echo -e "   MySQL Server:           ${YELLOW}$MYSQL_HOST${NC}"
echo -e "   SQL Server:             ${YELLOW}$SQL_HOST${NC}"
echo -e "   PostgreSQL Server:      ${YELLOW}$POSTGRES_HOST${NC}"
echo -e "   Communication Service:  ${YELLOW}$COMMUNICATION_SERVICE${NC}"
echo -e "   Key Vault:              ${YELLOW}$KEY_VAULT_URL${NC}"
echo -e "   Managed Identity:       ${YELLOW}$MANAGED_IDENTITY${NC}"
echo ""
echo -e "${CYAN}📝 Log Files:${NC}"
echo -e "   Deployment Log:         ${YELLOW}$LOG_FILE${NC}"
echo -e "   Redis Deploy Log:       ${YELLOW}/tmp/redis_deploy.log${NC}"
echo -e "   Cosmos Deploy Log:      ${YELLOW}/tmp/cosmos_deploy.log${NC}"
echo -e "   MySQL Deploy Log:       ${YELLOW}/tmp/mysql_deploy.log${NC}"
echo -e "   SQL Deploy Log:         ${YELLOW}/tmp/sql_deploy.log${NC}"
echo -e "   PostgreSQL Deploy Log:  ${YELLOW}/tmp/postgres_deploy.log${NC}"
echo ""
echo -e "${CYAN}🚀 Next Steps:${NC}"
echo -e "   1. Save suffix '${YELLOW}$SUFFIX${NC}' for service deployments"
echo -e "   2. Deploy services: ${BLUE}cd <service>/scripts && ./aca.sh $ENVIRONMENT${NC}"
echo ""
echo -e "${YELLOW}💾 Retrieve suffix later: ${BLUE}az group show -n $RESOURCE_GROUP --query \"tags.suffix\" -o tsv${NC}"
echo ""
