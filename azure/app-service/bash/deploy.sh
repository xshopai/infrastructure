#!/bin/bash

# =============================================================================
# xshopai Platform Deployment to Azure App Service
# =============================================================================
# Unified deployment script for infrastructure and services.
#
# Usage:
#   ./deploy.sh                              # Deploy all (infra + services)
#   ./deploy.sh --infra                      # Deploy infrastructure only
#   ./deploy.sh --services                   # Deploy services only
#   ./deploy.sh --service auth-service       # Deploy single service
#   ./deploy.sh --env production             # Specify environment
#   ./deploy.sh --location eastus            # Specify Azure region
#
# Examples:
#   ./deploy.sh                              # Interactive, deploy all
#   ./deploy.sh --env development --infra    # Deploy infra to dev
#   ./deploy.sh --services                   # Deploy all services (needs infra)
#   ./deploy.sh --service customer-ui        # Redeploy single service
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Docker installed and running (for service deployment)
#   - Contributor role on the subscription
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/infra"
SERVICES_DIR="$SCRIPT_DIR/services"

source "$SCRIPT_DIR/common.sh"

# -----------------------------------------------------------------------------
# Default Configuration
# -----------------------------------------------------------------------------
ENVIRONMENT=""
LOCATION="francecentral"
SUFFIX=""
PROJECT_NAME="xshopai"

# Deployment flags
DEPLOY_INFRA=false
DEPLOY_SERVICES=false
SINGLE_SERVICE=""

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --all                 Deploy infrastructure and all services (default)"
    echo "  --infra               Deploy infrastructure only"
    echo "  --services            Deploy all services only (requires existing infra)"
    echo "  --service NAME        Deploy a single service (requires existing infra)"
    echo "  --env ENV             Environment: dev or prod"
    echo "  --location REGION     Azure region (default: northeurope)"
    echo "  --suffix SUFFIX       Unique suffix for global resources (3-6 alphanumeric)"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                              # Interactive, deploy all"
    echo "  $0 --env development --infra    # Deploy infra to development"
    echo "  $0 --env development --services # Deploy services to development"
    echo "  $0 --service auth-service       # Redeploy single service"
    echo ""
    echo "Services available:"
    echo "  auth-service, user-service, product-service, inventory-service,"
    echo "  audit-service, notification-service, review-service, admin-service,"
    echo "  cart-service, chat-service, order-processor-service, order-service,"
    echo "  payment-service, web-bff, customer-ui, admin-ui"
}

parse_args() {
    # Default: deploy all if no flags specified
    local has_deploy_flag=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                DEPLOY_INFRA=true
                DEPLOY_SERVICES=true
                has_deploy_flag=true
                shift
                ;;
            --infra|-i)
                DEPLOY_INFRA=true
                has_deploy_flag=true
                shift
                ;;
            --services|-s)
                DEPLOY_SERVICES=true
                has_deploy_flag=true
                shift
                ;;
            --service)
                DEPLOY_SERVICES=true
                SINGLE_SERVICE="$2"
                has_deploy_flag=true
                shift 2
                ;;
            --env|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --location|-l)
                LOCATION="$2"
                shift 2
                ;;
            --suffix)
                SUFFIX="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Default to all if no deploy flag specified
    if [ "$has_deploy_flag" = false ]; then
        DEPLOY_INFRA=true
        DEPLOY_SERVICES=true
    fi
}

parse_args "$@"

# -----------------------------------------------------------------------------
# Setup Logging
# -----------------------------------------------------------------------------
SCRIPT_START_TIME=$SECONDS
LOG_FILE="/tmp/xshopai-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------
print_header "xshopai Platform Deployment"
echo -e "${CYAN}Log file: $LOG_FILE${NC}\n"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    print_info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi
print_success "Azure CLI installed"

# Check if logged in
if ! az account show &> /dev/null; then
    print_warning "Not logged into Azure. Initiating login..."
    az login
fi

# Ensure we're logged in as a user (not service principal) for Key Vault portal access
LOGIN_TYPE=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
if [ "$LOGIN_TYPE" = "servicePrincipal" ]; then
    print_warning "Currently logged in as Service Principal"
    print_warning "Key Vault secrets won't be viewable in Azure Portal without user login"
    echo ""
    read -p "Do you want to login as your user account? (recommended) [Y/n]: " LOGIN_CHOICE
    if [[ "$LOGIN_CHOICE" != "n" && "$LOGIN_CHOICE" != "N" ]]; then
        print_info "Opening browser for Azure login..."
        az login
        LOGIN_TYPE=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
    fi
fi

if [ "$LOGIN_TYPE" = "user" ]; then
    CURRENT_USER=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null)
    print_success "Logged into Azure as: $CURRENT_USER (user account)"
else
    CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null)
    print_warning "Logged into Azure as: Service Principal"
    print_warning "Key Vault secrets may not be viewable in portal"
fi

# Check Docker (only if deploying services)
if [ "$DEPLOY_SERVICES" = true ]; then
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed - will skip image building"
    elif ! docker info &> /dev/null; then
        print_warning "Docker is not running - will skip image building"
    else
        print_success "Docker is available"
    fi
fi

# -----------------------------------------------------------------------------
# Environment Selection
# -----------------------------------------------------------------------------
if [ -z "$ENVIRONMENT" ]; then
    echo ""
    echo "Select environment:"
    echo "  1) dev"
    echo "  2) prod"
    read -p "Enter choice [1]: " env_choice
    case "${env_choice:-1}" in
        1) ENVIRONMENT="dev" ;;
        2) ENVIRONMENT="prod" ;;
        *) ENVIRONMENT="dev" ;;
    esac
fi

SHORT_ENV="$ENVIRONMENT"

# -----------------------------------------------------------------------------
# Unique Suffix (for globally unique Azure resource names)
# -----------------------------------------------------------------------------
DEFAULT_SUFFIX=$(openssl rand -hex 2 2>/dev/null || date +%s | tail -c 5)

if [ -z "$SUFFIX" ]; then
    echo ""
    echo "Some Azure resources (ACR, Key Vault) require globally unique names."
    echo "Enter a unique suffix (3-6 lowercase letters/numbers)."
    read -p "Suffix [$DEFAULT_SUFFIX]: " SUFFIX
    SUFFIX="${SUFFIX:-$DEFAULT_SUFFIX}"
fi

# Validate suffix
if [[ ! "$SUFFIX" =~ ^[a-z0-9]{3,6}$ ]]; then
    print_error "Invalid suffix: $SUFFIX (must be 3-6 lowercase alphanumeric)"
    exit 1
fi
print_success "Suffix: $SUFFIX"

# -----------------------------------------------------------------------------
# Export Configuration
# -----------------------------------------------------------------------------
export ENVIRONMENT SHORT_ENV LOCATION SUFFIX PROJECT_NAME
export RESOURCE_GROUP="rg-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export ACR_NAME="acr${PROJECT_NAME}${SHORT_ENV}${SUFFIX}"
export APP_SERVICE_PLAN="asp-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export KEY_VAULT="kv-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export LOG_ANALYTICS="log-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export APP_INSIGHTS="appi-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export COSMOS_ACCOUNT="cosmos-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export POSTGRESQL_SERVER="psql-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export POSTGRES_SERVER="$POSTGRESQL_SERVER"  # Alias for ACA modules
export MYSQL_SERVER="mysql-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export SQL_SERVER="sql-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export REDIS_CACHE="redis-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
export REDIS_NAME="$REDIS_CACHE"  # Alias for ACA modules
export RABBITMQ_INSTANCE="aci-rabbitmq-${SHORT_ENV}-${SUFFIX}"

export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)

# Database credentials (generated for infra, loaded from KV for services-only)
export DB_ADMIN_USER="xshopadmin"

# -----------------------------------------------------------------------------
# Show Configuration
# -----------------------------------------------------------------------------
print_header "Deployment Configuration"
echo "Environment:        $ENVIRONMENT"
echo "Suffix:             $SUFFIX"
echo "Location:           $LOCATION"
echo "Subscription:       $SUBSCRIPTION_NAME"
echo ""
echo "Deploy Mode:"
[ "$DEPLOY_INFRA" = true ] && echo "  ✓ Infrastructure"
[ "$DEPLOY_SERVICES" = true ] && [ -z "$SINGLE_SERVICE" ] && echo "  ✓ All Services"
[ -n "$SINGLE_SERVICE" ] && echo "  ✓ Single Service: $SINGLE_SERVICE"
echo ""

if [ "$DEPLOY_INFRA" = true ]; then
    echo "Infrastructure Resources:"
    echo "  Resource Group:     $RESOURCE_GROUP"
    echo "  Key Vault:          $KEY_VAULT"
    echo "  ACR:                $ACR_NAME"
    echo "  App Service Plan:   $APP_SERVICE_PLAN"
    echo "  Log Analytics:      $LOG_ANALYTICS"
    echo "  Cosmos DB:          $COSMOS_ACCOUNT"
    echo "  PostgreSQL:         $POSTGRESQL_SERVER"
    echo "  MySQL:              $MYSQL_SERVER"
    echo "  SQL Server:         $SQL_SERVER"
    echo "  Redis:              $REDIS_CACHE"
    echo "  RabbitMQ:           $RABBITMQ_INSTANCE"
fi


# =============================================================================
# Phase 1: Infrastructure Deployment
# =============================================================================
deploy_infrastructure() {
    print_header "Phase 1: Infrastructure Deployment"
    
    # Generate unique passwords for each database type (no shared password)
    print_info "Generating database credentials (unique per database type)"
    export MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-mysqladmin}"
    export MYSQL_ADMIN_PASSWORD="${MYSQL_ADMIN_PASSWORD:-$(generate_password 'Mysql' 16)}"
    export POSTGRES_ADMIN_USER="${POSTGRES_ADMIN_USER:-pgadmin}"
    export POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-$(generate_password 'Pg' 16)}"
    export SQL_ADMIN_USER="${SQL_ADMIN_USER:-sqladmin}"
    export SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-$(generate_password 'Sql' 16)}"
    
    # -------------------------------------------------------------------------
    # Sequential Steps (dependencies required)
    # -------------------------------------------------------------------------
    local sequential_steps=(
        "01-resource-group.sh:deploy_resource_group:Creating Resource Group"
        "02-monitoring.sh:deploy_monitoring:Creating Monitoring Resources"
        "03-acr.sh:deploy_acr:Creating Container Registry"
        "04-app-service-plan.sh:deploy_app_service_plan:Creating App Service Plan"
    )
    
    local current=0
    local total=7  # 4 sequential + 1 parallel batch + RabbitMQ + KeyVault&Secrets
    
    for step in "${sequential_steps[@]}"; do
        IFS=':' read -r file func desc <<< "$step"
        current=$((current + 1))
        echo -e "\n${BLUE}[$current/$total] $desc${NC}"
        source "$INFRA_DIR/$file"
        $func || { print_error "$desc failed"; exit 1; }
    done
    
    # -------------------------------------------------------------------------
    # Parallel Steps (Data Resources - longest running, no dependencies)
    # -------------------------------------------------------------------------
    current=$((current + 1))
    echo -e "\n${BLUE}[$current/$total] Creating Data Resources (Parallel)${NC}"
    print_warning "Starting parallel deployment of data resources..."
    print_info "This will take 10-15 minutes total"
    
    # Source all data modules
    source "$INFRA_DIR/05-redis.sh"
    source "$INFRA_DIR/06-cosmos-db.sh"
    source "$INFRA_DIR/07-postgresql.sh"
    source "$INFRA_DIR/08-mysql.sh"
    source "$INFRA_DIR/09-sql-server.sh"
    
    # Run data resources in parallel
    deploy_redis > /tmp/redis_deploy.log 2>&1 &
    REDIS_PID=$!
    
    deploy_cosmos_db > /tmp/cosmos_deploy.log 2>&1 &
    COSMOS_PID=$!
    
    deploy_postgresql > /tmp/postgres_deploy.log 2>&1 &
    POSTGRES_PID=$!
    
    deploy_mysql > /tmp/mysql_deploy.log 2>&1 &
    MYSQL_PID=$!
    
    deploy_sql_server > /tmp/sql_deploy.log 2>&1 &
    SQL_PID=$!
    
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
        printf "\r   ⏱️  %3ds | Redis: %s | Cosmos: %s | PostgreSQL: %s | MySQL: %s | SQL: %s   " \
            "$ELAPSED" \
            "$($REDIS_DONE && echo '✅' || echo '⏳')" \
            "$($COSMOS_DONE && echo '✅' || echo '⏳')" \
            "$($POSTGRES_DONE && echo '✅' || echo '⏳')" \
            "$($MYSQL_DONE && echo '✅' || echo '⏳')" \
            "$($SQL_DONE && echo '✅' || echo '⏳')"
        
        $REDIS_DONE && $COSMOS_DONE && $MYSQL_DONE && $SQL_DONE && $POSTGRES_DONE && break
        sleep 5
    done
    echo ""
    
    # Check exit codes and capture any failures
    FAILED=0
    wait $REDIS_PID || { print_error "Redis deployment failed"; cat /tmp/redis_deploy.log; FAILED=1; }
    wait $COSMOS_PID || { print_error "Cosmos DB deployment failed"; cat /tmp/cosmos_deploy.log; FAILED=1; }
    wait $POSTGRES_PID || { print_error "PostgreSQL deployment failed"; cat /tmp/postgres_deploy.log; FAILED=1; }
    wait $MYSQL_PID || { print_error "MySQL deployment failed"; cat /tmp/mysql_deploy.log; FAILED=1; }
    wait $SQL_PID || { print_error "SQL Server deployment failed"; cat /tmp/sql_deploy.log; FAILED=1; }
    
    if [ $FAILED -eq 1 ]; then
        print_error "One or more data resources failed to deploy"
        exit 1
    fi
    print_success "All data resources deployed successfully"
    
    # Re-fetch all connection info (variables lost in parallel subshells)
    print_info "Fetching connection details from deployed resources..."
    
    # ACR credentials
    export ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
    export ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query username -o tsv 2>/dev/null || echo "")
    export ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query "passwords[0].value" -o tsv 2>/dev/null || echo "")
    
    # Redis
    export REDIS_HOST="${REDIS_CACHE}.redis.cache.windows.net"
    export REDIS_KEY=$(az redis list-keys --name "$REDIS_CACHE" --resource-group "$RESOURCE_GROUP" --query primaryKey -o tsv 2>/dev/null || echo "")
    export REDIS_CONNECTION="rediss://:${REDIS_KEY}@${REDIS_HOST}:6380"
    
    # Cosmos DB
    export COSMOS_ENDPOINT=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query documentEndpoint -o tsv 2>/dev/null || echo "")
    export COSMOS_CONNECTION=$(az cosmosdb keys list --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --type connection-strings --query "connectionStrings[0].connectionString" -o tsv 2>/dev/null || echo "")
    
    # PostgreSQL
    export POSTGRES_HOST="${POSTGRESQL_SERVER}.postgres.database.azure.com"
    export POSTGRESQL_HOST="$POSTGRES_HOST"
    export POSTGRESQL_CONNECTION="Host=$POSTGRES_HOST;Database=postgres;Username=${POSTGRES_ADMIN_USER};Password=${POSTGRES_ADMIN_PASSWORD};SslMode=Require"
    export POSTGRES_SERVER_CONNECTION="$POSTGRESQL_CONNECTION"
    
    # MySQL
    export MYSQL_HOST="${MYSQL_SERVER}.mysql.database.azure.com"
    
    # SQL Server
    export SQL_HOST="${SQL_SERVER}.database.windows.net"

    # RabbitMQ (ACI)
    export RABBITMQ_HOST=$(az container show \
        --name "$RABBITMQ_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "ipAddress.fqdn" -o tsv 2>/dev/null || echo "")
    
    # -------------------------------------------------------------------------
    # Final Sequential Steps
    # -------------------------------------------------------------------------
    current=$((current + 1))
    echo -e "\n${BLUE}[$current/$total] Creating RabbitMQ${NC}"
    source "$INFRA_DIR/10-rabbitmq.sh"
    deploy_rabbitmq || { print_error "RabbitMQ deployment failed"; exit 1; }
    
    current=$((current + 1))
    echo -e "\n${BLUE}[$current/$total] Creating Key Vault & Storing Secrets${NC}"
    source "$INFRA_DIR/11-keyvault.sh"
    deploy_keyvault || { print_error "Key Vault deployment failed"; exit 1; }

    # -------------------------------------------------------------------------
    # Export service-specific connection strings so service scripts work in the
    # combined infra+services run (same variable names loaded_infrastructure_config
    # loads from Key Vault for the services-only run path).
    # -------------------------------------------------------------------------
    print_info "Exporting service connection strings..."
    export ORDER_SERVICE_SQL_CONNECTION="Server=${SQL_HOST};Database=order_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    export PAYMENT_SERVICE_SQL_CONNECTION="Server=${SQL_HOST};Database=payment_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    export AUDIT_SERVICE_POSTGRES_URL="postgresql://${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/audit_service_db?sslmode=require"
    export ORDER_PROCESSOR_SERVICE_POSTGRES_URL="jdbc:postgresql://${POSTGRES_HOST}:5432/order_processor_db?user=${POSTGRES_ADMIN_USER}&password=${POSTGRES_ADMIN_PASSWORD}&ssl=true"
    export INVENTORY_SERVICE_MYSQL_URL="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306/inventory_service_db"

    print_success "Infrastructure deployment complete"
}

# =============================================================================
# Phase 2: Load Existing Infrastructure Config
# =============================================================================
load_infrastructure_config() {
    print_header "Loading Infrastructure Configuration"
    
    # Check if infrastructure exists
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        print_error "Resource group $RESOURCE_GROUP does not exist"
        print_info "Run with --infra flag first to deploy infrastructure"
        exit 1
    fi
    
    # Get ACR credentials
    export ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
    export ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username -o tsv 2>/dev/null)
    export ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv 2>/dev/null)
    
    # -------------------------------------------------------------------------
    # Load secrets from Key Vault
    # -------------------------------------------------------------------------
    print_info "Loading secrets from Key Vault: $KEY_VAULT"
    
    # Helper function to load secret
    load_secret() {
        az keyvault secret show --vault-name "$KEY_VAULT" --name "$1" --query value -o tsv 2>/dev/null || echo ""
    }
    
    # =========================================================================
    # SHARED SECRETS (Used by multiple services)
    # =========================================================================
    export JWT_SECRET=$(load_secret "jwt-secret")
    export JWT_ISSUER=$(load_secret "jwt-issuer")
    export JWT_AUDIENCE=$(load_secret "jwt-audience")
    export JWT_ALGORITHM=$(load_secret "jwt-algorithm")
    export JWT_EXPIRES_IN=$(load_secret "jwt-expires-in")
    export JWT_REFRESH_EXPIRES_IN=$(load_secret "jwt-refresh-expires-in")
    export RABBITMQ_URL=$(load_secret "rabbitmq-url")
    export APPINSIGHTS_CONNECTION_STRING=$(load_secret "appinsights-connection-string")
    
    # =========================================================================
    # SERVICE-SPECIFIC DATABASE CONNECTIONS
    # =========================================================================
    # MongoDB (Cosmos DB)
    export USER_SERVICE_MONGODB_URI=$(load_secret "user-service-mongodb-uri")
    export PRODUCT_SERVICE_MONGODB_URI=$(load_secret "product-service-mongodb-uri")
    export REVIEW_SERVICE_MONGODB_URI=$(load_secret "review-service-mongodb-uri")
    
    # PostgreSQL
    export AUDIT_SERVICE_POSTGRES_URL=$(load_secret "audit-service-postgres-url")
    export ORDER_PROCESSOR_SERVICE_POSTGRES_URL=$(load_secret "order-processor-service-postgres-url")
    
    # MySQL
    export INVENTORY_SERVICE_MYSQL_URL=$(load_secret "inventory-service-mysql-url")
    
    # SQL Server
    export ORDER_SERVICE_SQL_CONNECTION=$(load_secret "order-service-sql-connection")
    export PAYMENT_SERVICE_SQL_CONNECTION=$(load_secret "payment-service-sql-connection")
    
    # Redis
    export CART_SERVICE_REDIS_URL=$(load_secret "cart-service-redis-url")
    
    # =========================================================================
    # SERVICE-TO-SERVICE TOKENS
    # =========================================================================
    export ADMIN_SERVICE_TOKEN=$(load_secret "admin-service-token")
    export AUTH_SERVICE_TOKEN=$(load_secret "auth-service-token")
    export USER_SERVICE_TOKEN=$(load_secret "user-service-token")
    export PRODUCT_SERVICE_TOKEN=$(load_secret "product-service-token")
    export INVENTORY_SERVICE_TOKEN=$(load_secret "inventory-service-token")
    export CART_SERVICE_TOKEN=$(load_secret "cart-service-token")
    export ORDER_SERVICE_TOKEN=$(load_secret "order-service-token")
    export ORDER_PROCESSOR_SERVICE_TOKEN=$(load_secret "order-processor-service-token")
    export PAYMENT_SERVICE_TOKEN=$(load_secret "payment-service-token")
    export REVIEW_SERVICE_TOKEN=$(load_secret "review-service-token")
    export NOTIFICATION_SERVICE_TOKEN=$(load_secret "notification-service-token")
    export AUDIT_SERVICE_TOKEN=$(load_secret "audit-service-token")
    export CHAT_SERVICE_TOKEN=$(load_secret "chat-service-token")
    export WEB_BFF_TOKEN=$(load_secret "web-bff-token")
    
    # =========================================================================
    # AZURE OPENAI (chat-service)
    # =========================================================================
    export CHAT_SERVICE_OPENAI_ENDPOINT=$(load_secret "chat-service-openai-endpoint")
    export CHAT_SERVICE_OPENAI_API_KEY=$(load_secret "chat-service-openai-api-key")
    export CHAT_SERVICE_OPENAI_DEPLOYMENT=$(load_secret "chat-service-openai-deployment")
    
    print_success "Loaded secrets from Key Vault"

    # -------------------------------------------------------------------------
    # Load admin credentials (stored during infra deployment for services-only
    # re-deployment without re-running infrastructure)
    # -------------------------------------------------------------------------
    export MYSQL_ADMIN_USER=$(load_secret "mysql-admin-user")
    export MYSQL_ADMIN_PASSWORD=$(load_secret "mysql-admin-password")
    export POSTGRES_ADMIN_USER=$(load_secret "postgres-admin-user")
    export POSTGRES_ADMIN_PASSWORD=$(load_secret "postgres-admin-password")
    export SQL_ADMIN_USER=$(load_secret "sql-admin-user")
    export SQL_ADMIN_PASSWORD=$(load_secret "sql-admin-password")
    export RABBITMQ_USER=$(load_secret "rabbitmq-user")
    export RABBITMQ_PASSWORD=$(load_secret "rabbitmq-password")

    # Derive database host names from resource names (not stored in KV)
    export POSTGRES_HOST="${POSTGRESQL_SERVER}.postgres.database.azure.com"
    export MYSQL_HOST="${MYSQL_SERVER}.mysql.database.azure.com"
    export SQL_HOST="${SQL_SERVER}.database.windows.net"

    # APP_INSIGHTS aliases expected by service scripts
    export APP_INSIGHTS_CONNECTION="$APPINSIGHTS_CONNECTION_STRING"
    export APP_INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey -o tsv 2>/dev/null || echo "")

    # Reconstruct service-specific connection strings using loaded credentials
    # (ensures correct format regardless of what was stored in Key Vault)
    export ORDER_SERVICE_SQL_CONNECTION="Server=${SQL_HOST};Database=order_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    export PAYMENT_SERVICE_SQL_CONNECTION="Server=${SQL_HOST};Database=payment_service_db;User Id=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};TrustServerCertificate=True;MultipleActiveResultSets=true;Encrypt=True"
    export AUDIT_SERVICE_POSTGRES_URL="postgresql://${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/audit_service_db?sslmode=require"
    export ORDER_PROCESSOR_SERVICE_POSTGRES_URL="jdbc:postgresql://${POSTGRES_HOST}:5432/order_processor_db?user=${POSTGRES_ADMIN_USER}&password=${POSTGRES_ADMIN_PASSWORD}&ssl=true"
    export INVENTORY_SERVICE_MYSQL_URL="mysql+pymysql://${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@${MYSQL_HOST}:3306/inventory_service_db"
}

# =============================================================================
# Phase 3: Service Deployment
# =============================================================================
deploy_services() {
    print_header "Phase 2: Service Deployment"
    
    # Source service common functions
    source "$SERVICES_DIR/_common.sh"
    
    # Login to ACR
    print_info "Logging into ACR: $ACR_NAME"
    az acr login --name "$ACR_NAME" 2>/dev/null || print_warning "ACR login failed"
    
    if [ -n "$SINGLE_SERVICE" ]; then
        # Deploy single service
        deploy_single_service "$SINGLE_SERVICE"
    else
        # Deploy all services
        deploy_all_services
    fi
}

deploy_single_service() {
    local service="$1"
    local service_file="$SERVICES_DIR/${service}.sh"
    
    if [ ! -f "$service_file" ]; then
        print_error "Unknown service: $service"
        print_info "Available services: auth-service, user-service, product-service, etc."
        exit 1
    fi
    
    source "$service_file"
    local func_name="deploy_${service//-/_}"
    
    if $func_name; then
        print_success "Deployed: $service"
    else
        print_error "Failed to deploy: $service"
        exit 1
    fi
}

deploy_all_services() {
    local services=(
        "auth-service"
        "user-service"
        "product-service"
        "inventory-service"
        "audit-service"
        "notification-service"
        "review-service"
        "admin-service"
        "cart-service"
        "chat-service"
        "order-processor-service"
        "order-service"
        "payment-service"
        "web-bff"
        "customer-ui"
        "admin-ui"
    )
    
    local total=${#services[@]}
    local current=0
    local failed=()
    local succeeded=()
    
    for service in "${services[@]}"; do
        current=$((current + 1))
        echo -e "\n${BLUE}[$current/$total] Deploying: $service${NC}"
        
        local service_file="$SERVICES_DIR/${service}.sh"
        if [ -f "$service_file" ]; then
            source "$service_file"
            local func_name="deploy_${service//-/_}"
            if $func_name; then
                succeeded+=("$service")
            else
                failed+=("$service")
            fi
        else
            print_warning "Service file not found: $service"
            failed+=("$service")
        fi
    done
    
    # Summary
    echo ""
    print_header "Service Deployment Summary"
    
    if [ ${#succeeded[@]} -gt 0 ]; then
        print_success "Succeeded (${#succeeded[@]}):"
        for s in "${succeeded[@]}"; do
            echo "  ✓ $s"
        done
    fi
    
    if [ ${#failed[@]} -gt 0 ]; then
        print_error "Failed (${#failed[@]}):"
        for s in "${failed[@]}"; do
            echo "  ✗ $s"
        done
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

# Deploy infrastructure if requested
if [ "$DEPLOY_INFRA" = true ]; then
    deploy_infrastructure
fi

# Deploy services if requested
if [ "$DEPLOY_SERVICES" = true ]; then
    # If we didn't just deploy infra, load existing config
    if [ "$DEPLOY_INFRA" = false ]; then
        load_infrastructure_config
    fi
    deploy_services
fi

# =============================================================================
# Final Summary
# =============================================================================
TOTAL_TIME=$((SECONDS - SCRIPT_START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECS=$((TOTAL_TIME % 60))

print_header "Deployment Complete!"

echo -e "${GREEN}Environment:${NC}        $ENVIRONMENT"
echo -e "${GREEN}Suffix:${NC}             $SUFFIX"
echo -e "${GREEN}Resource Group:${NC}     $RESOURCE_GROUP"
echo -e "${GREEN}Total Time:${NC}         ${MINUTES}m ${SECS}s"
echo ""
echo -e "${CYAN}App URLs:${NC}"
echo "  Customer UI:  https://app-customer-ui-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
echo "  Admin UI:     https://app-admin-ui-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
echo "  Web BFF:      https://app-web-bff-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}.azurewebsites.net"
echo ""
echo -e "${CYAN}Azure Portal:${NC}"
echo "  https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
echo ""
echo -e "${CYAN}Log file:${NC} $LOG_FILE"
