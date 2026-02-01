#!/bin/bash

# =============================================================================
# Module 10: Java Services
# =============================================================================
# Builds and deploys Java services:
# - cart-service (port 8008) - Quarkus
# - order-processor-service (port 8007) - Spring Boot
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying Java Services"

# Default to build if not specified
BUILD_IMAGES="${BUILD_IMAGES:-true}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# =============================================================================
# Cart Service (Quarkus)
# =============================================================================
print_subheader "Cart Service (Quarkus - port 8008)"

CART_SERVICE_DIR="$SERVICES_DIR/cart-service"
CART_CONTAINER="xshopai-cart-service"
CART_IMAGE="xshopai/cart-service:${IMAGE_TAG}"
CART_PORT="8008"

if [ ! -d "$CART_SERVICE_DIR" ]; then
    print_error "Cart service directory not found: $CART_SERVICE_DIR"
else
    # Build image if requested
    if [ "$BUILD_IMAGES" = "true" ]; then
        build_service_image "cart-service" "$CART_SERVICE_DIR" "$IMAGE_TAG"
    fi
    
    # Stop existing container
    remove_container "$CART_CONTAINER"
    
    # Prepare environment file path
    env_file=""
    if [ -f "$CART_SERVICE_DIR/.env.local" ]; then
        env_file="$CART_SERVICE_DIR/.env.local"
    elif [ -f "$CART_SERVICE_DIR/.env" ]; then
        env_file="$CART_SERVICE_DIR/.env"
    fi
    
    # Run container
    docker_cmd="docker run -d \
        --name $CART_CONTAINER \
        --network $DOCKER_NETWORK \
        --restart unless-stopped \
        -p ${CART_PORT}:${CART_PORT} \
        -e QUARKUS_HTTP_PORT=${CART_PORT} \
        -e QUARKUS_PROFILE=dev \
        -e REDIS_HOST=xshopai-redis \
        -e REDIS_PORT=6379"
    
    if [ -n "$env_file" ]; then
        docker_cmd="$docker_cmd --env-file $env_file"
    fi
    
    docker_cmd="$docker_cmd $CART_IMAGE"
    eval "$docker_cmd"
    
    print_success "Cart service started on port $CART_PORT"
fi

# =============================================================================
# Order Processor Service (Spring Boot)
# =============================================================================
print_subheader "Order Processor Service (Spring Boot - port 8007)"

ORDER_PROC_SERVICE_DIR="$SERVICES_DIR/order-processor-service"
ORDER_PROC_CONTAINER="xshopai-order-processor-service"
ORDER_PROC_IMAGE="xshopai/order-processor-service:${IMAGE_TAG}"
ORDER_PROC_PORT="8007"

if [ ! -d "$ORDER_PROC_SERVICE_DIR" ]; then
    print_error "Order processor service directory not found: $ORDER_PROC_SERVICE_DIR"
else
    # Build image if requested
    if [ "$BUILD_IMAGES" = "true" ]; then
        build_service_image "order-processor-service" "$ORDER_PROC_SERVICE_DIR" "$IMAGE_TAG"
    fi
    
    # Stop existing container
    remove_container "$ORDER_PROC_CONTAINER"
    
    # Prepare environment file path
    env_file=""
    if [ -f "$ORDER_PROC_SERVICE_DIR/.env.local" ]; then
        env_file="$ORDER_PROC_SERVICE_DIR/.env.local"
    elif [ -f "$ORDER_PROC_SERVICE_DIR/.env" ]; then
        env_file="$ORDER_PROC_SERVICE_DIR/.env"
    fi
    
    # Run container
    docker_cmd="docker run -d \
        --name $ORDER_PROC_CONTAINER \
        --network $DOCKER_NETWORK \
        --restart unless-stopped \
        -p ${ORDER_PROC_PORT}:${ORDER_PROC_PORT} \
        -e SERVER_PORT=${ORDER_PROC_PORT} \
        -e SPRING_PROFILES_ACTIVE=dev \
        -e SPRING_DATASOURCE_URL=jdbc:postgresql://xshopai-order-processor-postgres:5432/order_processor_db \
        -e SPRING_DATASOURCE_USERNAME=postgres \
        -e SPRING_DATASOURCE_PASSWORD=postgres"
    
    if [ -n "$env_file" ]; then
        docker_cmd="$docker_cmd --env-file $env_file"
    fi
    
    docker_cmd="$docker_cmd $ORDER_PROC_IMAGE"
    eval "$docker_cmd"
    
    print_success "Order processor service started on port $ORDER_PROC_PORT"
fi

# =============================================================================
# Wait for services to start
# =============================================================================
print_step "Waiting for Java services to start..."
sleep 20

# =============================================================================
# Summary
# =============================================================================
print_header "Java Services Deployed"

echo -e "\n${CYAN}Service Endpoints:${NC}"
echo -e "  Cart Service:            ${GREEN}http://localhost:${CART_PORT}${NC}"
echo -e "  Order Processor Service: ${GREEN}http://localhost:${ORDER_PROC_PORT}${NC}"

print_success "Java services deployment complete"
