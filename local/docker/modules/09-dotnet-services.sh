#!/bin/bash

# =============================================================================
# Module 09: .NET Services
# =============================================================================
# Builds and deploys .NET/ASP.NET Core services:
# - order-service (port 8006)
# - payment-service (port 8009)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying .NET Services"

# Default to build if not specified
BUILD_IMAGES="${BUILD_IMAGES:-true}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# =============================================================================
# Helper function to deploy a .NET service
# =============================================================================
deploy_dotnet_service() {
    local service_name="$1"
    local service_port="$2"
    local service_dir="$3"
    local db_container="$4"
    local db_port="$5"
    local connection_string="$6"
    
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
    
    # Run container
    docker run -d \
        --name "$container_name" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${service_port}:${service_port}" \
        -e "ASPNETCORE_ENVIRONMENT=Development" \
        -e "ASPNETCORE_URLS=http://+:${service_port}" \
        -e "ConnectionStrings__DefaultConnection=${connection_string}" \
        "$image_name"
    
    print_success "$service_name started on port $service_port"
}

# =============================================================================
# Order Service
# =============================================================================
ORDER_SERVICE_DIR="$SERVICES_DIR/order-service"
ORDER_CONNECTION_STRING="Server=xshopai-order-sqlserver,1433;Database=order_service_db;User Id=sa;Password=Admin123!;TrustServerCertificate=True"
deploy_dotnet_service "order-service" "8006" "$ORDER_SERVICE_DIR" \
    "xshopai-order-sqlserver" "1433" "$ORDER_CONNECTION_STRING"

# =============================================================================
# Payment Service
# =============================================================================
PAYMENT_SERVICE_DIR="$SERVICES_DIR/payment-service"
PAYMENT_CONNECTION_STRING="Server=xshopai-payment-sqlserver,1433;Database=payment_service_db;User Id=sa;Password=Admin123!;TrustServerCertificate=True"
deploy_dotnet_service "payment-service" "8009" "$PAYMENT_SERVICE_DIR" \
    "xshopai-payment-sqlserver" "1433" "$PAYMENT_CONNECTION_STRING"

# =============================================================================
# Wait for services to start
# =============================================================================
print_step "Waiting for .NET services to start..."
sleep 15

# =============================================================================
# Summary
# =============================================================================
print_header ".NET Services Deployed"

echo -e "\n${CYAN}Service Endpoints:${NC}"
echo -e "  Order Service:   ${GREEN}http://localhost:8006${NC}"
echo -e "  Payment Service: ${GREEN}http://localhost:8009${NC}"

echo -e "\n${CYAN}Swagger UI:${NC}"
echo -e "  Order Service:   ${GREEN}http://localhost:8006/swagger${NC}"
echo -e "  Payment Service: ${GREEN}http://localhost:8009/swagger${NC}"

print_success ".NET services deployment complete"
