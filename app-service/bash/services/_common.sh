#!/bin/bash
# =============================================================================
# Service Deployment Common Functions
# =============================================================================

# Source code root (where service repos are located)
SERVICES_ROOT="${SERVICES_ROOT:-/c/gh/xshopai}"

# Temporary directory for local builds (Java, .NET)
BUILD_TMP_DIR="${BUILD_TMP_DIR:-/tmp/xshopai-builds}"

# -----------------------------------------------------------------------------
# Get Health Check Path for a Service
# Returns the appropriate health check endpoint based on service technology
# -----------------------------------------------------------------------------
get_health_check_path() {
    local service_name="$1"
    case "$service_name" in
        # Static UI apps (nginx) only expose /health
        customer-ui|admin-ui)
            echo "/health"
            ;;
        # All backend services expose /health/live
        *)
            echo "/health/live"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Load a secret from Azure Key Vault
# Usage: value=$(load_secret "my-secret-name")
# -----------------------------------------------------------------------------
load_secret() {
    local name="$1"
    if [ -z "$KEY_VAULT" ]; then
        print_warning "KEY_VAULT not set - cannot load secret: $name"
        echo ""
        return 1
    fi
    az keyvault secret show --vault-name "$KEY_VAULT" --name "$name" --query value -o tsv 2>/dev/null || echo ""
}

# -----------------------------------------------------------------------------
# Create App Service
# -----------------------------------------------------------------------------
create_app_service() {
    local service_name="$1"
    local runtime="$2"
    local app_name="app-${service_name}-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
    
    print_info "Creating App Service: $app_name"
    
    if az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_info "App Service already exists, updating: $app_name"
    else
        if az webapp create \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --runtime "$runtime" \
            --output none; then
            print_success "Created: $app_name"
        else
            print_error "Failed to create: $app_name"
            return 1
        fi
    fi
    
    # Enable managed identity
    az webapp identity assign \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --output none 2>/dev/null

    # Get health check path for this service
    local health_path
    health_path=$(get_health_check_path "$service_name")

    # Enable Always On and configure health check
    MSYS_NO_PATHCONV=1 az webapp config set \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --always-on true \
        --generic-configurations "{\"healthCheckPath\":\"$health_path\"}" \
        --output none 2>/dev/null
    
    print_info "Health check configured: $health_path"

    # Link Application Insights (if configured)
    if [ -n "$APP_INSIGHTS" ] && [ -n "$APP_INSIGHTS_CONNECTION" ]; then
        print_info "Linking Application Insights: $APP_INSIGHTS"
        
        # Get App Insights resource ID
        local app_insights_id
        app_insights_id=$(az monitor app-insights component show \
            --app "$APP_INSIGHTS" \
            --resource-group "$RESOURCE_GROUP" \
            --query id -o tsv 2>/dev/null)
        
        if [ -n "$app_insights_id" ]; then
            # Link App Insights to Web App using REST API (more reliable than CLI)
            local webapp_id
            webapp_id=$(az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)
            
            if [ -n "$webapp_id" ]; then
                # Update web app properties to link App Insights
                MSYS_NO_PATHCONV=1 az rest --method PATCH \
                    --uri "https://management.azure.com${webapp_id}?api-version=2023-01-01" \
                    --body "{\"properties\":{\"siteConfig\":{\"appSettings\":[{\"name\":\"APPINSIGHTS_INSTRUMENTATIONKEY\",\"value\":\"$APP_INSIGHTS_KEY\"},{\"name\":\"APPLICATIONINSIGHTS_CONNECTION_STRING\",\"value\":\"$APP_INSIGHTS_CONNECTION\"}]}}}" \
                    --output none 2>/dev/null || true
                print_success "Application Insights linked"
            fi
        fi
    fi
}

# -----------------------------------------------------------------------------
# Configure App Service Settings
# -----------------------------------------------------------------------------
configure_app_settings() {
    local app_name="$1"
    shift
    local settings=("$@")
    
    print_info "Configuring settings for $app_name..."
    
    az webapp config appsettings set \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "${settings[@]}" \
        --output none 2>/dev/null
}

# -----------------------------------------------------------------------------
# Configure Diagnostic Settings (stream App Service logs to Log Analytics)
# -----------------------------------------------------------------------------
configure_diagnostic_settings() {
    local app_name="$1"

    if [ -z "$LOG_ANALYTICS" ]; then
        print_warning "LOG_ANALYTICS not set - skipping diagnostic settings"
        return 0
    fi

    local workspace_id
    workspace_id=$(MSYS_NO_PATHCONV=1 az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv 2>/dev/null)

    if [ -z "$workspace_id" ]; then
        print_warning "Log Analytics workspace not found - skipping diagnostic settings"
        return 0
    fi

    print_info "Configuring diagnostic settings for $app_name..."

    # Delete existing setting first so create is always idempotent
    MSYS_NO_PATHCONV=1 az monitor diagnostic-settings delete \
        --name "diag-${app_name}" \
        --resource "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --resource-namespace "Microsoft.Web" \
        --resource-type "sites" \
        --output none 2>/dev/null

    if MSYS_NO_PATHCONV=1 az monitor diagnostic-settings create \
        --name "diag-${app_name}" \
        --resource "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --resource-namespace "Microsoft.Web" \
        --resource-type "sites" \
        --workspace "$workspace_id" \
        --logs '[{"category":"AppServiceHTTPLogs","enabled":true},{"category":"AppServiceConsoleLogs","enabled":true},{"category":"AppServiceAppLogs","enabled":true},{"category":"AppServicePlatformLogs","enabled":true}]' \
        --metrics '[{"category":"AllMetrics","enabled":true}]' \
        --output none; then
        print_success "Diagnostic settings configured: $app_name"
    else
        print_warning "Failed to configure diagnostic settings: $app_name"
    fi
}

# -----------------------------------------------------------------------------
# Get Runtime-Specific Startup Command
# Returns empty string for runtimes where App Service uses the default
# -----------------------------------------------------------------------------
get_startup_command() {
    local service_name="$1"
    case "$service_name" in
        # FastAPI: Gunicorn + Uvicorn workers; $PORT is set automatically by App Service
        product-service)
            echo "gunicorn --worker-class uvicorn.workers.UvicornWorker -w 2 -b 0.0.0.0:\$PORT main:app"
            ;;
        # Flask: run migrations then start Gunicorn; $PORT is set automatically by App Service
        # FLASK_SKIP_AZURE_MONITOR prevents Azure Monitor initializing during flask db upgrade
        inventory-service)
            echo "FLASK_SKIP_AZURE_MONITOR=true flask db upgrade && exec gunicorn --bind 0.0.0.0:\$PORT --workers 2 --timeout 120 --preload run:app"
            ;;
        # React SPAs: serve the built static output as a single-page app
        customer-ui|admin-ui)
            echo "pm2 serve /home/site/wwwroot/build --no-daemon --spa -p \$PORT"
            ;;
        # Node.js backends: App Service runs 'npm start' by default
        # .NET:           App Service runs the published DLL directly
        # Java:           App Service runs the JAR directly
        *)
            echo ""
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Configure App Service Startup Command
# -----------------------------------------------------------------------------
configure_startup_command() {
    local app_name="$1"
    local startup_cmd="$2"

    if [ -n "$startup_cmd" ]; then
        az webapp config set \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --startup-file "$startup_cmd" \
            --output none 2>/dev/null && \
        print_info "Startup command: $startup_cmd" || \
        print_warning "Failed to set startup command on $app_name"
    fi
}

# -----------------------------------------------------------------------------
# Deploy an artifact (zip or jar) to App Service with retry.
# New App Services can return HTTP 400 before Kudu has fully initialised;
# retrying after a short wait resolves this reliably.
# -----------------------------------------------------------------------------
deploy_artifact() {
    local app_name="$1"
    local src_path="$2"
    local type="$3"   # zip | jar
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local tmp_log
        tmp_log=$(mktemp)

        # --async true: use Azure's async deployment API instead of the synchronous
        # Kudu endpoint. However, the CLI still polls the async task URL, so without
        # a timeout it will still wait up to 10 minutes for the site process to start.
        #
        # timeout 120: cap polling at 120s — enough for upload + Oryx build (~17s
        # typical) but not for site startup (which can take minutes and is handled
        # by verify_deployments() after all services are deployed).
        #
        # Exit code 124 = bash timeout reached. If the build already succeeded at
        # that point, startup is just in progress — treat as success.
        # Any other non-zero = genuine upload/auth/quota failure — retry or fail.
        timeout 120 az webapp deploy \
            --name "$app_name" \
            --resource-group "$RESOURCE_GROUP" \
            --src-path "$src_path" \
            --type "$type" \
            --async true \
            --output none 2>"$tmp_log"
        local exit_code=$?

        if [ $exit_code -eq 0 ] || \
           { [ $exit_code -eq 124 ] && grep -q "Build successful" "$tmp_log" 2>/dev/null; }; then
            rm -f "$tmp_log"
            print_success "URL: https://${app_name}.azurewebsites.net"
            return 0
        fi

        cat "$tmp_log" >&2
        rm -f "$tmp_log"

        if [ $attempt -lt $max_attempts ]; then
            print_warning "Deploy attempt $attempt/$max_attempts failed — retrying in 20s..."
            sleep 20
        fi
        ((attempt++))
    done

    print_error "Deployment failed after $max_attempts attempts: $app_name"
    return 1
}

# -----------------------------------------------------------------------------
# Create a zip archive from a directory with POSIX (forward-slash) entry paths.
#
# 'zip' is the fast path (Linux/macOS/CI/WSL). On Windows Git Bash where 'zip'
# is absent, Python's zipfile module is used instead — it always writes '/'
# path separators regardless of the host OS. This matters because the Linux
# App Service Kudu rsync engine treats '\' as part of the filename and fails
# with "Invalid argument" on every file when backslash-path zips are unpacked.
#
# Usage: create_zip_posix <source_dir> <output_zip_path>
# -----------------------------------------------------------------------------
create_zip_posix() {
    local src_dir="$1"
    local zip_path="$2"

    if command -v zip &>/dev/null; then
        (cd "$src_dir" && zip -r "$zip_path" . -q)
    else
        # Windows fallback: Python zipfile always uses '/' separators
        local py_cmd
        py_cmd=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
        if [ -z "$py_cmd" ]; then
            print_error "Neither 'zip' nor Python found — cannot create deployment zip"
            return 1
        fi
        # Git Bash POSIX paths (e.g. /tmp/...) are not understood by Windows
        # Python; convert them to Windows paths first.
        local win_src win_zip
        win_src=$(cygpath -w "$src_dir" 2>/dev/null || echo "$src_dir")
        win_zip=$(cygpath -w "$zip_path" 2>/dev/null || echo "$zip_path")
        "$py_cmd" -c "
import zipfile, os, sys
sd, zp = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zp, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(sd):
        for f in files:
            fp = os.path.join(root, f)
            z.write(fp, os.path.relpath(fp, sd).replace(os.sep, '/'))
" "$win_src" "$win_zip"
    fi
}

# -----------------------------------------------------------------------------
# Build Java Service (Maven) and Deploy JAR
# Spring Boot: produces a self-contained fat JAR
# Quarkus:     requires quarkus.package.jar.type=uber-jar in application.properties
# -----------------------------------------------------------------------------
build_and_deploy_java() {
    local service_name="$1"
    local app_name="$2"
    local service_path="$SERVICES_ROOT/$service_name"

    print_info "Building Java service: $service_name (Maven)"

    if ! command -v mvn &> /dev/null; then
        print_error "Maven (mvn) not found — cannot build $service_name"
        return 1
    fi

    if ! (cd "$service_path" && mvn package -DskipTests -q 2>&1); then
        print_error "Maven build failed for $service_name"
        return 1
    fi

    # Prefer Quarkus runner JAR, fall back to Spring Boot fat JAR
    local jar_path
    jar_path=$(find "$service_path/target" -maxdepth 1 -name "*-runner.jar" 2>/dev/null | head -1)
    [ -z "$jar_path" ] && \
        jar_path=$(find "$service_path/target" -maxdepth 1 -name "*.jar" \
            ! -name "*-sources.jar" ! -name "*-javadoc.jar" ! -name "original-*.jar" 2>/dev/null | head -1)

    if [ -z "$jar_path" ]; then
        print_error "No deployable JAR found in $service_path/target/"
        return 1
    fi

    print_info "Deploying JAR: $(basename "$jar_path")"

    deploy_artifact "$app_name" "$jar_path" "jar"
}

# -----------------------------------------------------------------------------
# Publish .NET Service and Deploy Zip
# -----------------------------------------------------------------------------
build_and_deploy_dotnet() {
    local service_name="$1"
    local app_name="$2"
    local service_path="$SERVICES_ROOT/$service_name"
    local tmp_dir="$BUILD_TMP_DIR/$service_name"
    local publish_dir="$tmp_dir/publish"

    print_info "Publishing .NET service: $service_name"

    if ! command -v dotnet &> /dev/null; then
        print_error "dotnet CLI not found — cannot build $service_name"
        return 1
    fi

    rm -rf "$tmp_dir" && mkdir -p "$publish_dir"

    # Find the main (non-test) .csproj
    local csproj
    csproj=$(find "$service_path" -name "*.csproj" | grep -iv "test" | head -1)

    if [ -z "$csproj" ]; then
        print_error "No .csproj found in $service_path"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Clean stale MSBuild incremental-build cache (obj/) — without this, a
    # prior partial/parallel build can leave locked cache files that cause
    # MSB3492 errors and a non-zero exit code on subsequent publishes.
    dotnet clean "$csproj" -c Release --nologo -q 2>/dev/null || true

    if ! dotnet publish "$csproj" -c Release -o "$publish_dir" --nologo -q; then
        print_error "dotnet publish failed for $service_name"
        rm -rf "$tmp_dir"
        return 1
    fi

    local zip_path="$tmp_dir/${service_name}.zip"
    create_zip_posix "$publish_dir" "$zip_path" || { rm -rf "$tmp_dir"; return 1; }

    deploy_artifact "$app_name" "$zip_path" "zip"
    local rc=$?
    rm -rf "$tmp_dir"
    return $rc
}

# -----------------------------------------------------------------------------
# Build and Deploy a Service Using Native App Service Runtime (No Docker)
#
# Strategy by runtime:
#   Java       — Maven package locally, deploy JAR
#   .NET       — dotnet publish locally, deploy zip
#   Node.js    — zip source, Oryx builds on App Service (npm install + npm start)
#   Python     — zip source, Oryx builds on App Service (pip install + startup cmd)
# -----------------------------------------------------------------------------
build_and_deploy_service() {
    local service_name="$1"
    local runtime="$2"
    local app_name="$3"
    local service_path="$SERVICES_ROOT/$service_name"

    if [ ! -d "$service_path" ]; then
        print_warning "Service directory not found: $service_path — skipping deploy"
        return 1
    fi

    # Java: build locally, deploy JAR
    if [[ "$runtime" == JAVA* ]]; then
        build_and_deploy_java "$service_name" "$app_name"
        return $?
    fi

    # .NET: publish locally, deploy zip
    if [[ "$runtime" == DOTNETCORE* ]]; then
        build_and_deploy_dotnet "$service_name" "$app_name"
        return $?
    fi

    # Node.js / Python: zip source and let Oryx build on App Service
    local tmp_dir="$BUILD_TMP_DIR/$service_name"
    rm -rf "$tmp_dir" && mkdir -p "$tmp_dir"
    local zip_path="$tmp_dir/${service_name}.zip"

    print_info "Creating deployment package: $service_name"

    if command -v zip &>/dev/null; then
        (cd "$service_path" && zip -r "$zip_path" . -q \
            -x "*.git/*" \
            -x "node_modules/*" \
            -x "__pycache__/*" \
            -x "*.pyc" \
            -x ".pytest_cache/*" \
            -x "*.egg-info/*" \
            -x "dist/*" \
            -x "build/*" \
            -x ".env" \
            -x ".env.*" \
            -x "logs/*" \
            -x "*.log")
    else
        # Windows — use PowerShell. First copy to a staging dir to honour exclusions.
        local stage_dir="$tmp_dir/stage"
        mkdir -p "$stage_dir"
        (cd "$service_path" && \
            find . -type f \
                ! -path "*/.git/*" \
                ! -path "*/node_modules/*" \
                ! -path "*/__pycache__/*" \
                ! -name "*.pyc" \
                ! -path "*/.pytest_cache/*" \
                ! -path "*/*.egg-info/*" \
                ! -path "*/dist/*" \
                ! -path "*/build/*" \
                ! -name ".env" \
                ! -name ".env.*" \
                ! -path "*/logs/*" \
                ! -name "*.log" \
            | while IFS= read -r f; do
                dest="$stage_dir/$f"
                mkdir -p "$(dirname "$dest")"
                cp "$f" "$dest"
            done
        )
        create_zip_posix "$stage_dir" "$zip_path" || { rm -rf "$tmp_dir"; return 1; }
        rm -rf "$stage_dir"
    fi

    deploy_artifact "$app_name" "$zip_path" "zip"
    local rc=$?
    rm -rf "$tmp_dir"
    return $rc
}

# -----------------------------------------------------------------------------
# Map ENVIRONMENT to NODE_ENV (Node.js requires: development, production, test)
# -----------------------------------------------------------------------------
get_node_env() {
    case "${ENVIRONMENT:-dev}" in
        dev|development) echo "development" ;;
        prod|production) echo "production" ;;
        test|testing)    echo "test" ;;
        *)               echo "production" ;;  # default to production for safety
    esac
}

# -----------------------------------------------------------------------------
# Full Service Deployment (create + configure + build + push + deploy)
# -----------------------------------------------------------------------------
deploy_service_full() {
    local service_name="$1"
    local runtime="$2"
    local port="$3"
    shift 3
    local extra_settings=("$@")
    
    print_header "Deploying: $service_name"

    # 1. Create App Service (pre-compute name to avoid capturing print output via $())
    local app_name="app-${service_name}-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
    create_app_service "$service_name" "$runtime" || return 1
    
    # 2. Common settings shared across all runtimes
    local common_settings=(
        "PORT=$port"
        "ENVIRONMENT=$ENVIRONMENT"
        "SCM_DO_BUILD_DURING_DEPLOYMENT=true"
        "APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONNECTION"
        "APPINSIGHTS_INSTRUMENTATIONKEY=$APP_INSIGHTS_KEY"
    )

    # NODE_ENV is Node.js-specific; only set it for Node.js runtimes
    if [[ "$runtime" == NODE* ]]; then
        common_settings+=("NODE_ENV=$(get_node_env)")
    fi

    # ApplicationInsightsAgent_EXTENSION_VERSION is Java-only: tells App Service to attach
    # the Application Insights Java agent JAR to the JVM. Has no effect on other runtimes.
    if [[ "$runtime" == JAVA* ]]; then
        common_settings+=("ApplicationInsightsAgent_EXTENSION_VERSION=~3")
    fi

    # 3. Configure all settings
    configure_app_settings "$app_name" "${common_settings[@]}" "${extra_settings[@]}"

    # 4. Configure diagnostic settings (logs + metrics → Log Analytics)
    configure_diagnostic_settings "$app_name"

    # 5. Configure startup command (Python and UI services need an explicit command)
    local startup_cmd
    startup_cmd=$(get_startup_command "$service_name")
    configure_startup_command "$app_name" "$startup_cmd"

    # 6. Build and deploy using native runtime (no Docker, no ACR)
    build_and_deploy_service "$service_name" "$runtime" "$app_name" || return 1

    print_success "Completed: $service_name"
}
