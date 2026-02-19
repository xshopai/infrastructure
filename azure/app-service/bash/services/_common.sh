#!/bin/bash
# =============================================================================
# Service Deployment Common Functions
# =============================================================================

# Source code root (where service repos are located)
SERVICES_ROOT="${SERVICES_ROOT:-/c/gh/xshopai}"

# Docker image tag
IMAGE_TAG="${IMAGE_TAG:-latest}"

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
        print_warning "App Service already exists: $app_name"
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

    # Enable Always On (services have publisher and consumer responsibilities)
    az webapp config set \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --always-on true \
        --output none 2>/dev/null

    # Configure container registry
    az webapp config container set \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --docker-registry-server-url "https://${ACR_LOGIN_SERVER}" \
        --docker-registry-server-user "$ACR_USERNAME" \
        --docker-registry-server-password "$ACR_PASSWORD" \
        --output none 2>/dev/null
        
    echo "$app_name"
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
# Build Docker Image
# -----------------------------------------------------------------------------
build_image() {
    local service_name="$1"
    local service_path="$SERVICES_ROOT/$service_name"
    local image_name="$ACR_LOGIN_SERVER/$service_name:$IMAGE_TAG"
    
    print_info "Building Docker image: $image_name"
    
    if [ ! -f "$service_path/Dockerfile" ]; then
        print_warning "No Dockerfile found at $service_path"
        return 1
    fi
    
    if docker build -t "$image_name" "$service_path"; then
        print_success "Built: $image_name"
        echo "$image_name"
    else
        print_error "Failed to build: $service_name"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Push Image to ACR
# -----------------------------------------------------------------------------
push_image() {
    local image_name="$1"
    
    print_info "Pushing to ACR: $image_name"
    
    if docker push "$image_name"; then
        print_success "Pushed: $image_name"
    else
        print_error "Failed to push: $image_name"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Deploy Container to App Service
# -----------------------------------------------------------------------------
deploy_container() {
    local app_name="$1"
    local image_name="$2"
    
    print_info "Deploying container to $app_name"
    
    if az webapp config container set \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --docker-custom-image-name "$image_name" \
        --output none; then
        print_success "Deployed: $app_name"
    else
        print_error "Failed to deploy: $app_name"
        return 1
    fi
    
    # Restart to pick up new image
    az webapp restart --name "$app_name" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null
    
    print_success "URL: https://${app_name}.azurewebsites.net"
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
    
    # 1. Create App Service
    local app_name
    app_name=$(create_app_service "$service_name" "$runtime") || return 1
    
    # 2. Common settings
    local common_settings=(
        "WEBSITES_PORT=$port"
        "PORT=$port"
        "ENVIRONMENT=$ENVIRONMENT"
        "APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONNECTION"
        "APPINSIGHTS_INSTRUMENTATIONKEY=$APP_INSIGHTS_KEY"
    )
    
    # 3. Configure all settings
    configure_app_settings "$app_name" "${common_settings[@]}" "${extra_settings[@]}"
    
    # 4. Build image (skip if no Docker or Dockerfile)
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        local image_name
        if image_name=$(build_image "$service_name"); then
            # 5. Push to ACR
            if push_image "$image_name"; then
                # 6. Deploy container
                deploy_container "$app_name" "$image_name"
            fi
        fi
    else
        print_warning "Docker not available - skipping image build/deploy"
        print_info "Run deploy again with Docker to deploy container"
    fi
    
    print_success "Completed: $service_name"
}
