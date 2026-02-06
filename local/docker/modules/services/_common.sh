#!/bin/bash

# =============================================================================
# Common Service Deployment Functions
# =============================================================================
# Shared functions for deploying individual services with optional Dapr sidecar.
# This file should be sourced by individual service deployment scripts.
#
# Features:
#   - Service container deployment
#   - Optional Dapr sidecar support
#   - Environment file handling
#   - Health check support
# =============================================================================

# Source the main common.sh if not already sourced
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$DOCKER_NETWORK" ]; then
    source "$MODULES_DIR/common.sh"
fi

# Default configuration
IMAGE_TAG="${IMAGE_TAG:-latest}"
DAPR_ENABLED="${DAPR_ENABLED:-false}"
DAPR_IMAGE="${DAPR_IMAGE:-daprio/daprd:1.12.0}"

# =============================================================================
# Deploy a service container (with optional Dapr sidecar)
# =============================================================================
# Arguments:
#   $1 - service_name (e.g., "auth-service")
#   $2 - service_port (e.g., "8004")
#   $3 - extra_env (optional, e.g., "-e MONGODB_HOST=xshopai-auth-mongodb")
#   $4 - dapr_components_path (optional, e.g., ".dapr/components")
#
# Environment variables:
#   IMAGE_TAG - Docker image tag (default: latest)
#   DAPR_ENABLED - Enable Dapr sidecar (default: false)
#   BUILD_IMAGES - Build images before deploying (default: false)
# =============================================================================
deploy_service() {
    local service_name="$1"
    local service_port="$2"
    local extra_env="${3:-}"
    local dapr_components_path="${4:-}"
    
    local container_name="xshopai-${service_name}"
    local image_name="xshopai/${service_name}:${IMAGE_TAG}"
    local service_dir="$SERVICES_DIR/${service_name}"
    
    print_subheader "Deploying ${service_name} (port ${service_port})"
    
    # Check if service directory exists
    if [ ! -d "$service_dir" ]; then
        print_error "Service directory not found: $service_dir"
        return 1
    fi
    
    # Build image if requested or if image doesn't exist
    if [ "${BUILD_IMAGES:-false}" = "true" ]; then
        print_info "Building image (--build flag)"
        build_service_image "$service_name" "$service_dir" "$IMAGE_TAG"
    elif ! docker image inspect "$image_name" &> /dev/null; then
        print_warning "Image not found locally, building: $image_name"
        build_service_image "$service_name" "$service_dir" "$IMAGE_TAG"
    else
        print_info "Using existing image: $image_name"
    fi
    
    # Stop existing containers
    remove_container "$container_name"
    if [ "$DAPR_ENABLED" = "true" ]; then
        remove_container "${container_name}-dapr"
    fi
    
    # Prepare environment file path
    local env_file=""
    if [ -f "$service_dir/.env.docker" ]; then
        env_file="$service_dir/.env.docker"
    elif [ -f "$service_dir/.env.local" ]; then
        env_file="$service_dir/.env.local"
    elif [ -f "$service_dir/.env" ]; then
        env_file="$service_dir/.env"
    fi
    
    # Build docker run command
    local docker_cmd="docker run -d \
        --name $container_name \
        --network $DOCKER_NETWORK \
        --restart unless-stopped \
        -p ${service_port}:${service_port}"
    
    # Add environment file if exists
    if [ -n "$env_file" ]; then
        docker_cmd="$docker_cmd --env-file $env_file"
    fi
    
    # Add extra environment variables
    if [ -n "$extra_env" ]; then
        docker_cmd="$docker_cmd $extra_env"
    fi
    
    # Add Dapr-related environment variables if Dapr is enabled
    if [ "$DAPR_ENABLED" = "true" ]; then
        docker_cmd="$docker_cmd \
            -e DAPR_HTTP_PORT=3500 \
            -e DAPR_GRPC_PORT=50001"
    fi
    
    # Add image name
    docker_cmd="$docker_cmd $image_name"
    
    # Run service container
    eval "$docker_cmd"
    print_success "${service_name} container started"
    
    # Deploy Dapr sidecar if enabled
    if [ "$DAPR_ENABLED" = "true" ]; then
        deploy_dapr_sidecar "$service_name" "$service_port" "$container_name" "$dapr_components_path"
    fi
    
    # Wait for service to be ready
    wait_for_container "$container_name" 30
    
    print_success "${service_name} is ready on port ${service_port}"
}

# =============================================================================
# Deploy Dapr sidecar for a service
# =============================================================================
deploy_dapr_sidecar() {
    local app_id="$1"
    local app_port="$2"
    local app_container="$3"
    local components_path="${4:-}"
    
    local sidecar_name="${app_container}-dapr"
    local service_dir="$SERVICE_REPOS_DIR/${app_id}"
    
    print_step "Starting Dapr sidecar for ${app_id}..."
    
    # Ensure Dapr image is available
    ensure_image "$DAPR_IMAGE"
    
    # Build Dapr sidecar command
    local dapr_cmd="docker run -d \
        --name $sidecar_name \
        --network $DOCKER_NETWORK \
        --restart unless-stopped \
        -e DAPR_APP_ID=$app_id \
        -e DAPR_APP_PORT=$app_port"
    
    # Mount components path if specified
    if [ -n "$components_path" ] && [ -d "$service_dir/$components_path" ]; then
        dapr_cmd="$dapr_cmd -v $service_dir/$components_path:/components"
    fi
    
    # Add Dapr command arguments
    dapr_cmd="$dapr_cmd $DAPR_IMAGE ./daprd \
        --app-id $app_id \
        --app-port $app_port \
        --dapr-http-port 3500 \
        --dapr-grpc-port 50001 \
        --log-level warn"
    
    # Add components path to Dapr if available
    if [ -n "$components_path" ] && [ -d "$service_dir/$components_path" ]; then
        dapr_cmd="$dapr_cmd --resources-path /components"
    fi
    
    # Configure Dapr to connect to the app container
    # Using Docker network, containers can reach each other by name
    dapr_cmd="$dapr_cmd --app-channel-address $app_container"
    
    eval "$dapr_cmd"
    print_success "Dapr sidecar started for ${app_id}"
}

# =============================================================================
# Deploy Node.js service
# =============================================================================
deploy_nodejs_service() {
    local service_name="$1"
    local service_port="$2"
    local extra_env="${3:-}"
    local dapr_components="${4:-}"
    
    # Add Node.js specific environment
    local nodejs_env="-e NODE_ENV=development -e PORT=${service_port}"
    
    if [ -n "$extra_env" ]; then
        nodejs_env="$nodejs_env $extra_env"
    fi
    
    deploy_service "$service_name" "$service_port" "$nodejs_env" "$dapr_components"
}

# =============================================================================
# Deploy Python service
# =============================================================================
deploy_python_service() {
    local service_name="$1"
    local service_port="$2"
    local extra_env="${3:-}"
    local dapr_components="${4:-}"
    
    # Add Python specific environment
    local python_env="-e ENVIRONMENT=development -e PORT=${service_port}"
    
    if [ -n "$extra_env" ]; then
        python_env="$python_env $extra_env"
    fi
    
    deploy_service "$service_name" "$service_port" "$python_env" "$dapr_components"
}

# =============================================================================
# Deploy .NET service
# =============================================================================
deploy_dotnet_service() {
    local service_name="$1"
    local service_port="$2"
    local connection_string="${3:-}"
    local extra_env="${4:-}"
    local dapr_components="${5:-}"
    
    # Add .NET specific environment
    local dotnet_env="-e ASPNETCORE_ENVIRONMENT=Development \
        -e ASPNETCORE_URLS=http://+:${service_port}"
    
    if [ -n "$connection_string" ]; then
        dotnet_env="$dotnet_env -e \"ConnectionStrings__DefaultConnection=$connection_string\""
    fi
    
    if [ -n "$extra_env" ]; then
        dotnet_env="$dotnet_env $extra_env"
    fi
    
    deploy_service "$service_name" "$service_port" "$dotnet_env" "$dapr_components"
}

# =============================================================================
# Deploy Java service
# =============================================================================
deploy_java_service() {
    local service_name="$1"
    local service_port="$2"
    local framework="${3:-spring}"  # spring or quarkus
    local extra_env="${4:-}"
    local dapr_components="${5:-}"
    
    local java_env=""
    
    if [ "$framework" = "quarkus" ]; then
        java_env="-e QUARKUS_HTTP_PORT=${service_port} -e QUARKUS_PROFILE=dev"
    else
        java_env="-e SERVER_PORT=${service_port} -e SPRING_PROFILES_ACTIVE=docker"
    fi
    
    if [ -n "$extra_env" ]; then
        java_env="$java_env $extra_env"
    fi
    
    deploy_service "$service_name" "$service_port" "$java_env" "$dapr_components"
}

# =============================================================================
# Deploy frontend service
# =============================================================================
deploy_frontend() {
    local service_name="$1"
    local external_port="$2"
    local extra_env="${3:-}"
    
    local container_name="xshopai-${service_name}"
    local image_name="xshopai/${service_name}:${IMAGE_TAG}"
    local service_dir="$SERVICE_REPOS_DIR/${service_name}"
    
    print_subheader "Deploying ${service_name} (port ${external_port})"
    
    # Check if service directory exists
    if [ ! -d "$service_dir" ]; then
        print_error "Service directory not found: $service_dir"
        return 1
    fi
    
    # Build image if requested or if image doesn't exist
    if [ "${BUILD_IMAGES:-false}" = "true" ]; then
        print_info "Building image (--build flag)"
        build_service_image "$service_name" "$service_dir" "$IMAGE_TAG"
    elif ! docker image inspect "$image_name" &> /dev/null; then
        print_warning "Image not found locally, building: $image_name"
        build_service_image "$service_name" "$service_dir" "$IMAGE_TAG"
    else
        print_info "Using existing image: $image_name"
    fi
    
    # Stop existing container
    remove_container "$container_name"
    
    # Build docker run command (frontend typically maps port 80 internally)
    local docker_cmd="docker run -d \
        --name $container_name \
        --network $DOCKER_NETWORK \
        --restart unless-stopped \
        -p ${external_port}:80"
    
    # Add extra environment variables
    if [ -n "$extra_env" ]; then
        docker_cmd="$docker_cmd $extra_env"
    fi
    
    # Add image name
    docker_cmd="$docker_cmd $image_name"
    
    # Run container
    eval "$docker_cmd"
    
    print_success "${service_name} started on port ${external_port}"
}
