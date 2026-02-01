#!/bin/bash

# =============================================================================
# Common Functions and Variables for xshopai Local Docker Deployment
# =============================================================================
# This file contains shared utilities used by all deployment modules.
# Source this file at the beginning of each module script.
# =============================================================================

# -----------------------------------------------------------------------------
# Colors for output
# -----------------------------------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Directory Configuration
# -----------------------------------------------------------------------------
# Get the directory where common.sh is located
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULES_DIR="$COMMON_DIR"
export SCRIPTS_DIR="$(dirname "$COMMON_DIR")"
export LOCAL_DIR="$(dirname "$SCRIPTS_DIR")"
export INFRA_DIR="$(dirname "$LOCAL_DIR")"
export WORKSPACE_DIR="$(dirname "$INFRA_DIR")"

# Service directories
export SERVICES_DIR="$WORKSPACE_DIR"

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------
export DOCKER_NETWORK="xshopai-network"

# -----------------------------------------------------------------------------
# Print functions
# -----------------------------------------------------------------------------
print_header() {
    echo -e "\n${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==============================================================================${NC}\n"
}

print_subheader() {
    echo -e "\n${CYAN}------------------------------------------------------------------------------${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}------------------------------------------------------------------------------${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_step() {
    echo -e "${MAGENTA}→ $1${NC}"
}

# -----------------------------------------------------------------------------
# Docker utility functions
# -----------------------------------------------------------------------------

# Check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Create network if it doesn't exist
ensure_network() {
    if ! docker network inspect "$DOCKER_NETWORK" &> /dev/null; then
        print_step "Creating Docker network: $DOCKER_NETWORK"
        docker network create "$DOCKER_NETWORK"
        print_success "Network created: $DOCKER_NETWORK"
    else
        print_info "Network already exists: $DOCKER_NETWORK"
    fi
}

# Check if container is running
is_container_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Check if container exists (running or stopped)
container_exists() {
    local container_name="$1"
    docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Wait for container to be healthy
wait_for_container() {
    local container_name="$1"
    local max_attempts="${2:-30}"
    local attempt=1

    print_step "Waiting for $container_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null | grep -q "healthy"; then
            print_success "$container_name is healthy"
            return 0
        elif docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null | grep -q "running"; then
            # If no healthcheck, just check if running
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -z "$health_status" ] || [ "$health_status" == "<no value>" ]; then
                sleep 2
                print_success "$container_name is running (no healthcheck)"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo ""
    print_warning "$container_name may not be fully ready (timed out after ${max_attempts}s)"
    return 1
}

# Stop and remove container
remove_container() {
    local container_name="$1"
    
    if container_exists "$container_name"; then
        print_step "Stopping container: $container_name"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
        print_success "Removed container: $container_name"
    fi
}

# Pull image if not exists
ensure_image() {
    local image_name="$1"
    
    if ! docker image inspect "$image_name" &> /dev/null; then
        print_step "Pulling image: $image_name"
        docker pull "$image_name"
        print_success "Pulled image: $image_name"
    else
        print_info "Image exists: $image_name"
    fi
}

# Build service image
build_service_image() {
    local service_name="$1"
    local service_dir="$2"
    local image_tag="${3:-latest}"
    local dockerfile="${4:-Dockerfile}"
    
    local full_image_name="xshopai/${service_name}:${image_tag}"
    
    print_step "Building image: $full_image_name"
    
    if [ ! -f "$service_dir/$dockerfile" ]; then
        print_error "Dockerfile not found: $service_dir/$dockerfile"
        return 1
    fi
    
    docker build -t "$full_image_name" -f "$service_dir/$dockerfile" "$service_dir"
    print_success "Built image: $full_image_name"
}

# Run container with standard options
run_container() {
    local container_name="$1"
    local image="$2"
    local port_mapping="$3"
    shift 3
    local extra_args=("$@")
    
    print_step "Starting container: $container_name"
    
    docker run -d \
        --name "$container_name" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "$port_mapping" \
        "${extra_args[@]}" \
        "$image"
    
    print_success "Started container: $container_name"
}

# Get container logs
show_logs() {
    local container_name="$1"
    local lines="${2:-50}"
    
    print_subheader "Logs for $container_name (last $lines lines)"
    docker logs --tail "$lines" "$container_name"
}

# -----------------------------------------------------------------------------
# Service status functions
# -----------------------------------------------------------------------------
print_service_status() {
    local container_name="$1"
    local port="$2"
    local db_type="$3"
    
    if is_container_running "$container_name"; then
        echo -e "  ${GREEN}●${NC} $container_name (port $port) - ${db_type}"
    else
        echo -e "  ${RED}○${NC} $container_name (port $port) - ${db_type}"
    fi
}

# -----------------------------------------------------------------------------
# Environment file handling
# -----------------------------------------------------------------------------
load_env_file() {
    local env_file="$1"
    
    if [ -f "$env_file" ]; then
        export $(grep -v '^#' "$env_file" | xargs)
        print_info "Loaded environment from: $env_file"
    else
        print_warning "Environment file not found: $env_file"
    fi
}

# -----------------------------------------------------------------------------
# Cleanup functions
# -----------------------------------------------------------------------------
cleanup_volumes() {
    local volume_prefix="${1:-xshopai}"
    
    print_step "Removing volumes with prefix: $volume_prefix"
    docker volume ls --filter "name=$volume_prefix" -q | xargs -r docker volume rm
    print_success "Volumes removed"
}

cleanup_network() {
    if docker network inspect "$DOCKER_NETWORK" &> /dev/null; then
        print_step "Removing network: $DOCKER_NETWORK"
        docker network rm "$DOCKER_NETWORK" 2>/dev/null || true
        print_success "Network removed: $DOCKER_NETWORK"
    fi
}
