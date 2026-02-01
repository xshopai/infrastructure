#!/bin/bash

# =============================================================================
# Module 07: Node.js Services
# =============================================================================
# Builds and deploys Node.js/Express services:
# - auth-service (port 8004)
# - user-service (port 8002)
# - admin-service (port 8003)
# - review-service (port 8010)
# - audit-service (port 8012)
# - notification-service (port 8011)
# - chat-service (port 8013)
# - web-bff (port 8014)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying Node.js Services"

# Default to build if not specified
BUILD_IMAGES="${BUILD_IMAGES:-true}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# =============================================================================
# Helper function to deploy a Node.js service
# =============================================================================
deploy_nodejs_service() {
    local service_name="$1"
    local service_port="$2"
    local service_dir="$3"
    local depends_on="${4:-}"
    local extra_env="${5:-}"
    
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
        -e PORT=${service_port} \
        -e NODE_ENV=development"
    
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
# Auth Service
# =============================================================================
AUTH_SERVICE_DIR="$SERVICES_DIR/auth-service"
deploy_nodejs_service "auth-service" "8004" "$AUTH_SERVICE_DIR" "" \
    "-e MONGODB_HOST=xshopai-auth-mongodb -e MONGODB_PORT=27017"

# =============================================================================
# User Service
# =============================================================================
USER_SERVICE_DIR="$SERVICES_DIR/user-service"
deploy_nodejs_service "user-service" "8002" "$USER_SERVICE_DIR" "" \
    "-e MONGODB_HOST=xshopai-user-mongodb -e MONGODB_PORT=27017"

# =============================================================================
# Admin Service
# =============================================================================
ADMIN_SERVICE_DIR="$SERVICES_DIR/admin-service"
deploy_nodejs_service "admin-service" "8003" "$ADMIN_SERVICE_DIR"

# =============================================================================
# Review Service
# =============================================================================
REVIEW_SERVICE_DIR="$SERVICES_DIR/review-service"
deploy_nodejs_service "review-service" "8010" "$REVIEW_SERVICE_DIR" "" \
    "-e MONGODB_HOST=xshopai-review-mongodb -e MONGODB_PORT=27017"

# =============================================================================
# Audit Service
# =============================================================================
AUDIT_SERVICE_DIR="$SERVICES_DIR/audit-service"
deploy_nodejs_service "audit-service" "8012" "$AUDIT_SERVICE_DIR" "" \
    "-e POSTGRES_HOST=xshopai-audit-postgres -e POSTGRES_PORT=5432"

# =============================================================================
# Notification Service
# =============================================================================
NOTIFICATION_SERVICE_DIR="$SERVICES_DIR/notification-service"
deploy_nodejs_service "notification-service" "8011" "$NOTIFICATION_SERVICE_DIR" "" \
    "-e SMTP_HOST=xshopai-mailpit -e SMTP_PORT=1025"

# =============================================================================
# Chat Service
# =============================================================================
CHAT_SERVICE_DIR="$SERVICES_DIR/chat-service"
deploy_nodejs_service "chat-service" "8013" "$CHAT_SERVICE_DIR"

# =============================================================================
# Web BFF
# =============================================================================
WEB_BFF_DIR="$SERVICES_DIR/web-bff"
deploy_nodejs_service "web-bff" "8014" "$WEB_BFF_DIR"

# =============================================================================
# Wait for services to start
# =============================================================================
print_step "Waiting for Node.js services to start..."
sleep 10

# =============================================================================
# Summary
# =============================================================================
print_header "Node.js Services Deployed"

echo -e "\n${CYAN}Service Endpoints:${NC}"
echo -e "  Auth Service:         ${GREEN}http://localhost:8004${NC}"
echo -e "  User Service:         ${GREEN}http://localhost:8002${NC}"
echo -e "  Admin Service:        ${GREEN}http://localhost:8003${NC}"
echo -e "  Review Service:       ${GREEN}http://localhost:8010${NC}"
echo -e "  Audit Service:        ${GREEN}http://localhost:8012${NC}"
echo -e "  Notification Service: ${GREEN}http://localhost:8011${NC}"
echo -e "  Chat Service:         ${GREEN}http://localhost:8013${NC}"
echo -e "  Web BFF:              ${GREEN}http://localhost:8014${NC}"

print_success "Node.js services deployment complete"
