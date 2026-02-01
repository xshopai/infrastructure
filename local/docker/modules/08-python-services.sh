#!/bin/bash

# =============================================================================
# Module 08: Python Services
# =============================================================================
# Builds and deploys Python/FastAPI services:
# - product-service (port 8001)
# - inventory-service (port 8005)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying Python Services"

# Default to build if not specified
BUILD_IMAGES="${BUILD_IMAGES:-true}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# =============================================================================
# Helper function to deploy a Python service
# =============================================================================
deploy_python_service() {
    local service_name="$1"
    local service_port="$2"
    local service_dir="$3"
    local extra_env="${4:-}"
    
    local container_name="xshopai-${service_name}"
    local image_name="xshopai/${service_name}:${IMAGE_TAG}"
    
    print_subheader "$service_name (port $service_port)"
    
    # Check if service directory exists
    if [ ! -d "$service_dir" ]; then
        print_error "Service directory not found: $service_dir"
        return 1
    fi
    
    # Build image if requested
    if [ "$BUILD_IMAGES" = "true" ]; then
        build_service_image "$service_name" "$service_dir" "$IMAGE_TAG"
    fi
    
    # Stop existing container
    if is_container_running "$container_name"; then
        print_info "$service_name is already running, stopping..."
        remove_container "$container_name"
    else
        remove_container "$container_name"
    fi
    
    # Prepare environment file path
    local env_file=""
    if [ -f "$service_dir/.env.local" ]; then
        env_file="$service_dir/.env.local"
    elif [ -f "$service_dir/.env" ]; then
        env_file="$service_dir/.env"
    fi
    
    # Build docker run command
    local docker_cmd="docker run -d \
        --name $container_name \
        --network $DOCKER_NETWORK \
        --restart unless-stopped \
        -p ${service_port}:${service_port} \
        -e PORT=${service_port}"
    
    # Add environment file if exists
    if [ -n "$env_file" ]; then
        docker_cmd="$docker_cmd --env-file $env_file"
    fi
    
    # Add extra environment variables
    if [ -n "$extra_env" ]; then
        docker_cmd="$docker_cmd $extra_env"
    fi
    
    # Add image name
    docker_cmd="$docker_cmd $image_name"
    
    # Run container
    eval "$docker_cmd"
    
    print_success "$service_name started on port $service_port"
}

# =============================================================================
# Product Service
# =============================================================================
PRODUCT_SERVICE_DIR="$SERVICES_DIR/product-service"
deploy_python_service "product-service" "8001" "$PRODUCT_SERVICE_DIR" \
    "-e MONGODB_HOST=xshopai-product-mongodb -e MONGODB_PORT=27017 -e ENVIRONMENT=development"

# =============================================================================
# Inventory Service
# =============================================================================
INVENTORY_SERVICE_DIR="$SERVICES_DIR/inventory-service"
deploy_python_service "inventory-service" "8005" "$INVENTORY_SERVICE_DIR" \
    "-e MYSQL_HOST=xshopai-inventory-mysql -e MYSQL_PORT=3306 -e ENVIRONMENT=development"

# =============================================================================
# Wait for services to start
# =============================================================================
print_step "Waiting for Python services to start..."
sleep 10

# =============================================================================
# Summary
# =============================================================================
print_header "Python Services Deployed"

echo -e "\n${CYAN}Service Endpoints:${NC}"
echo -e "  Product Service:   ${GREEN}http://localhost:8001${NC}"
echo -e "  Inventory Service: ${GREEN}http://localhost:8005${NC}"

echo -e "\n${CYAN}API Documentation:${NC}"
echo -e "  Product Service:   ${GREEN}http://localhost:8001/docs${NC}"
echo -e "  Inventory Service: ${GREEN}http://localhost:8005/docs${NC}"

print_success "Python services deployment complete"
