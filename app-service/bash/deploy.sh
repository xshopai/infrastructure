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
#   - dotnet CLI installed (for .NET services)
#   - Maven (mvn) installed (for Java services)
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
    echo "  --location REGION     Azure region (default: francecentral)"
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
    # In CI environments skip the interactive prompt and proceed as-is
    if [ "${CI:-false}" != "true" ]; then
        echo ""
        read -p "Do you want to login as your user account? (recommended) [Y/n]: " LOGIN_CHOICE
        if [[ "$LOGIN_CHOICE" != "n" && "$LOGIN_CHOICE" != "N" ]]; then
            print_info "Opening browser for Azure login..."
            az login
            LOGIN_TYPE=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
        fi
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
    echo "Key Vault requires a globally unique name."
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
export AZURE_OPENAI_NAME="oai-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"

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
    echo "  App Service Plan:   $APP_SERVICE_PLAN"
    echo "  Log Analytics:      $LOG_ANALYTICS"
    echo "  Cosmos DB:          $COSMOS_ACCOUNT"
    echo "  PostgreSQL:         $POSTGRESQL_SERVER"
    echo "  MySQL:              $MYSQL_SERVER"
    echo "  SQL Server:         $SQL_SERVER"
    echo "  Redis:              $REDIS_CACHE"
    echo "  RabbitMQ:           $RABBITMQ_INSTANCE"
    echo "  Azure OpenAI:       $AZURE_OPENAI_NAME"
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
        "03-app-service-plan.sh:deploy_app_service_plan:Creating App Service Plan"
    )

    local current=0
    local total=7  # 3 sequential + 1 parallel batch + RabbitMQ + OpenAI + KeyVault&Secrets
    
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
    source "$INFRA_DIR/04-redis.sh"
    source "$INFRA_DIR/05-cosmos-db.sh"
    source "$INFRA_DIR/06-postgresql.sh"
    source "$INFRA_DIR/07-mysql.sh"
    source "$INFRA_DIR/08-sql-server.sh"
    
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

    # Redis
    export REDIS_HOST="${REDIS_CACHE}.redis.cache.windows.net"
    export REDIS_KEY=$(az redis list-keys --name "$REDIS_CACHE" --resource-group "$RESOURCE_GROUP" --query primaryKey -o tsv 2>/dev/null || echo "")
    
    # Cosmos DB
    export COSMOS_ENDPOINT=$(az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query documentEndpoint -o tsv 2>/dev/null || echo "")
    export COSMOS_CONNECTION=$(az cosmosdb keys list --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --type connection-strings --query "connectionStrings[0].connectionString" -o tsv 2>/dev/null || echo "")
    
    # PostgreSQL
    export POSTGRES_HOST="${POSTGRESQL_SERVER}.postgres.database.azure.com"
    
    # MySQL
    export MYSQL_HOST="${MYSQL_SERVER}.mysql.database.azure.com"
    
    # SQL Server
    export SQL_HOST="${SQL_SERVER}.database.windows.net"

    # Note: RABBITMQ_HOST is exported by deploy_rabbitmq() below after ACI creation

    # -------------------------------------------------------------------------
    # Final Sequential Steps
    # -------------------------------------------------------------------------
    current=$((current + 1))
    echo -e "\n${BLUE}[$current/$total] Creating RabbitMQ${NC}"
    source "$INFRA_DIR/09-rabbitmq.sh"
    deploy_rabbitmq || { print_error "RabbitMQ deployment failed"; exit 1; }
    
    current=$((current + 1))
    echo -e "\n${BLUE}[$current/$total] Creating Azure OpenAI${NC}"
    source "$INFRA_DIR/10-azure-openai.sh"
    deploy_azure_openai || { print_error "Azure OpenAI deployment failed"; exit 1; }

    current=$((current + 1))
    echo -e "\n${BLUE}[$current/$total] Creating Key Vault & Storing Secrets${NC}"
    source "$INFRA_DIR/11-keyvault.sh"
    deploy_keyvault || { print_error "Key Vault deployment failed"; exit 1; }

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
    
    # -------------------------------------------------------------------------
    # Load only what's needed as environment variables for service deployment.
    # Service scripts load all other secrets directly from KV via load_secret().
    # -------------------------------------------------------------------------
    print_info "Loading configuration from Key Vault: $KEY_VAULT"

    # Helper function to load secret
    load_secret() {
        az keyvault secret show --vault-name "$KEY_VAULT" --name "$1" --query value -o tsv 2>/dev/null || echo ""
    }

    # Application Insights — injected into all services by deploy_service_full in _common.sh
    export APP_INSIGHTS_CONNECTION=$(load_secret "appinsights-connection-string")
    export APP_INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey -o tsv 2>/dev/null || echo "")

    # Redis — cart-service reads REDIS_HOST and REDIS_KEY directly from env vars
    export REDIS_HOST="${REDIS_CACHE}.redis.cache.windows.net"
    export REDIS_KEY=$(az redis list-keys --name "$REDIS_CACHE" --resource-group "$RESOURCE_GROUP" --query primaryKey -o tsv 2>/dev/null || echo "")

    print_success "Infrastructure configuration loaded"
}

# =============================================================================
# Phase 3: Service Deployment
# =============================================================================
deploy_services() {
    print_header "Phase 2: Service Deployment"
    
    # Source service common functions
    source "$SERVICES_DIR/_common.sh"

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
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local deploy_start=$SECONDS

    # Pre-source all service files before forking so that every subshell
    # inherits the deploy_* functions without needing to re-source.
    for service in "${services[@]}"; do
        local service_file="$SERVICES_DIR/${service}.sh"
        [ -f "$service_file" ] && source "$service_file"
    done

    print_info "Launching all $total service deployments in parallel..."
    print_info "Per-service logs: $tmp_dir/<service>.log"
    echo ""

    # ---------------------------------------------------------------------------
    # Launch every service deployment as a background subshell.
    # Each writes a per-service log and a status file (OK / FAILED) on exit.
    # ---------------------------------------------------------------------------
    for service in "${services[@]}"; do
        (
            set +e          # Don't let individual failures kill the subshell
            local log="$tmp_dir/${service}.log"
            local func="deploy_${service//-/_}"
            if declare -f "$func" &>/dev/null; then
                "$func" > "$log" 2>&1
                rc=$?
            else
                echo "ERROR: deploy function '$func' not found — was ${service}.sh sourced?" > "$log"
                rc=1
            fi
            [ $rc -eq 0 ] && echo "OK" > "$tmp_dir/${service}.status" \
                           || echo "FAILED" > "$tmp_dir/${service}.status"
        ) &
    done

    # ---------------------------------------------------------------------------
    # Live progress counter — poll until all status files are written.
    # NOTE: use 'if' not '&&' — with set -e, a short-circuited '&&' whose
    # left side returns 1 (file absent) will kill the parent shell.
    # ---------------------------------------------------------------------------
    while true; do
        local n=0
        for service in "${services[@]}"; do
            if [ -f "$tmp_dir/${service}.status" ]; then
                n=$((n + 1))
            fi
        done
        printf "\r  ⏱  %3ds — %d/%d services complete   " \
            "$((SECONDS - deploy_start))" "$n" "$total"
        if [ "$n" -eq "$total" ]; then
            break
        fi
        sleep 5
    done
    wait || true  # reap background jobs; '|| true' prevents set -e on failed jobs
    echo ""

    # ---------------------------------------------------------------------------
    # Collect results; print full log for any failed service
    # ---------------------------------------------------------------------------
    local succeeded=() failed=()
    for service in "${services[@]}"; do
        local status
        status=$(cat "$tmp_dir/${service}.status" 2>/dev/null || echo "UNKNOWN")
        if [ "$status" = "OK" ]; then
            succeeded+=("$service")
        else
            failed+=("$service")
        fi
    done

    for service in "${failed[@]}"; do
        echo ""
        print_error "=== ${service} deployment log ==="
        cat "$tmp_dir/${service}.log" >&2 || true
        echo ""
    done

    # Deployment summary
    print_header "Service Deployment Summary"
    if [ ${#succeeded[@]} -gt 0 ]; then
        print_success "Deployed (${#succeeded[@]}):"
        for s in "${succeeded[@]}"; do
            local url
            url=$(grep -o 'https://app-[^ ]*' "$tmp_dir/${s}.log" 2>/dev/null | tail -1)
            echo "  ✓ $s${url:+ → $url}"
        done
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        print_error "Failed (${#failed[@]}):"
        for s in "${failed[@]}"; do echo "  ✗ $s"; done
    fi

    rm -rf "$tmp_dir"

    # ---------------------------------------------------------------------------
    # Health verification — all deployments are done, poll health endpoints now
    # ---------------------------------------------------------------------------
    if [ ${#succeeded[@]} -gt 0 ]; then
        local health_tmp
        health_tmp=$(mktemp -d)
        for service in "${succeeded[@]}"; do
            _start_health_poller "$service" "$health_tmp" &
        done
        _wait_for_health_results "${succeeded[@]}" "$health_tmp"
    fi

    [ ${#failed[@]} -eq 0 ]
}

# -----------------------------------------------------------------------------
# _start_health_poller SERVICE TMP_DIR
# Background poller: polls the service's /health endpoint every VERIFY_INTERVAL
# seconds until it gets HTTP 200/204 or VERIFY_TIMEOUT is reached.
# -----------------------------------------------------------------------------
_start_health_poller() {
    local service="$1"
    local tmp_dir="$2"
    local VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-300}"
    local VERIFY_INTERVAL=15

    local app_name="app-${service}-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
    local base_url="https://${app_name}.azurewebsites.net"

    case "$service" in
        order-processor-service) local path="/actuator/health" ;;
        customer-ui|admin-ui)    local path="/" ;;
        *)                       local path="/health" ;;
    esac

    local url="${base_url}${path}"
    local elapsed=0

    while [ $elapsed -lt $VERIFY_TIMEOUT ]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)
        if [[ "$http_code" =~ ^(200|204)$ ]]; then
            echo "OK" > "$tmp_dir/$service"
            return 0
        fi
        sleep $VERIFY_INTERVAL
        elapsed=$((elapsed + VERIFY_INTERVAL))
    done
    echo "TIMEOUT" > "$tmp_dir/$service"
}

# -----------------------------------------------------------------------------
# _wait_for_health_results SERVICES... TMP_DIR
# Waits for all pollers to write their result files, showing a live counter,
# then prints the final healthy / unhealthy report.
# -----------------------------------------------------------------------------
_wait_for_health_results() {
    # Last argument is tmp_dir; everything before it is services
    local args=("$@")
    local tmp_dir="${args[-1]}"
    local services=("${args[@]:0:${#args[@]}-1}")

    [ ${#services[@]} -eq 0 ] && return 0

    print_header "Post-Deployment Health Verification"
    print_info "Polling in parallel (timeout: ${VERIFY_TIMEOUT:-300}s) — started alongside deployments..."

    local start=$SECONDS
    while true; do
        local done_count=0
        for service in "${services[@]}"; do
            if [ -f "$tmp_dir/$service" ]; then
                done_count=$((done_count + 1))
            fi
        done
        printf "\r  ⏱  %3ds — %d/%d services confirmed   " \
            "$((SECONDS - start))" "$done_count" "${#services[@]}"
        if [ $done_count -eq ${#services[@]} ]; then
            break
        fi
        sleep 5
    done
    wait || true
    echo ""

    local healthy=() unhealthy=()
    for service in "${services[@]}"; do
        local result
        result=$(cat "$tmp_dir/$service" 2>/dev/null || echo "UNKNOWN")
        if [ "$result" = "OK" ]; then
            healthy+=("$service")
        else
            unhealthy+=("$service")
        fi
    done
    rm -rf "$tmp_dir"

    echo ""
    if [ ${#healthy[@]} -gt 0 ]; then
        print_success "Healthy (${#healthy[@]}):"
        for s in "${healthy[@]}"; do echo "  ✓ $s"; done
    fi
    if [ ${#unhealthy[@]} -gt 0 ]; then
        print_warning "Did not respond within ${VERIFY_TIMEOUT:-300}s (${#unhealthy[@]}):"
        for s in "${unhealthy[@]}"; do echo "  ✗ $s"; done
        print_info "Check logs: https://<app-name>.scm.azurewebsites.net/api/logs/docker"
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
