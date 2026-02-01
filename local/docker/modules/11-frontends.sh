#!/bin/bash

# =============================================================================
# Module 11: Frontend Applications
# =============================================================================
# Builds and deploys frontend applications:
# - customer-ui (port 3000)
# - admin-ui (port 3001)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying Frontend Applications"

# Default to build if not specified
BUILD_IMAGES="${BUILD_IMAGES:-true}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# =============================================================================
# Customer UI (React)
# =============================================================================
print_subheader "Customer UI (React - port 3000)"

CUSTOMER_UI_DIR="$SERVICES_DIR/customer-ui"
CUSTOMER_UI_CONTAINER="xshopai-customer-ui"
CUSTOMER_UI_IMAGE="xshopai/customer-ui:${IMAGE_TAG}"
CUSTOMER_UI_PORT="3000"

if [ ! -d "$CUSTOMER_UI_DIR" ]; then
    print_error "Customer UI directory not found: $CUSTOMER_UI_DIR"
else
    # Build image if requested
    if [ "$BUILD_IMAGES" = "true" ]; then
        build_service_image "customer-ui" "$CUSTOMER_UI_DIR" "$IMAGE_TAG"
    fi
    
    # Stop existing container
    remove_container "$CUSTOMER_UI_CONTAINER"
    
    # Run container
    docker run -d \
        --name "$CUSTOMER_UI_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${CUSTOMER_UI_PORT}:80" \
        -e REACT_APP_BFF_URL=http://localhost:8014 \
        "$CUSTOMER_UI_IMAGE"
    
    print_success "Customer UI started on port $CUSTOMER_UI_PORT"
fi

# =============================================================================
# Admin UI (React)
# =============================================================================
print_subheader "Admin UI (React - port 3001)"

ADMIN_UI_DIR="$SERVICES_DIR/admin-ui"
ADMIN_UI_CONTAINER="xshopai-admin-ui"
ADMIN_UI_IMAGE="xshopai/admin-ui:${IMAGE_TAG}"
ADMIN_UI_PORT="3001"

if [ ! -d "$ADMIN_UI_DIR" ]; then
    print_error "Admin UI directory not found: $ADMIN_UI_DIR"
else
    # Build image if requested
    if [ "$BUILD_IMAGES" = "true" ]; then
        build_service_image "admin-ui" "$ADMIN_UI_DIR" "$IMAGE_TAG"
    fi
    
    # Stop existing container
    remove_container "$ADMIN_UI_CONTAINER"
    
    # Run container
    docker run -d \
        --name "$ADMIN_UI_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${ADMIN_UI_PORT}:80" \
        -e REACT_APP_ADMIN_SERVICE_URL=http://localhost:8003 \
        "$ADMIN_UI_IMAGE"
    
    print_success "Admin UI started on port $ADMIN_UI_PORT"
fi

# =============================================================================
# Wait for frontends to start
# =============================================================================
print_step "Waiting for frontend applications to start..."
sleep 5

# =============================================================================
# Summary
# =============================================================================
print_header "Frontend Applications Deployed"

echo -e "\n${CYAN}Application URLs:${NC}"
echo -e "  Customer UI: ${GREEN}http://localhost:${CUSTOMER_UI_PORT}${NC}"
echo -e "  Admin UI:    ${GREEN}http://localhost:${ADMIN_UI_PORT}${NC}"

print_success "Frontend applications deployment complete"
