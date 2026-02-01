#!/bin/bash

# =============================================================================
# xshopai Local Docker Cleanup Script
# =============================================================================
# Removes all xshopai Docker containers, volumes, and networks
#
# Usage:
#   ./cleanup.sh [options]
#
# Options:
#   --containers    Remove only containers
#   --volumes       Remove only volumes
#   --network       Remove only network
#   --images        Remove built images
#   --all           Remove everything (default)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

# Parse arguments
CLEAN_CONTAINERS=false
CLEAN_VOLUMES=false
CLEAN_NETWORK=false
CLEAN_IMAGES=false
CLEAN_ALL=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --containers)
            CLEAN_ALL=false
            CLEAN_CONTAINERS=true
            shift
            ;;
        --volumes)
            CLEAN_ALL=false
            CLEAN_VOLUMES=true
            shift
            ;;
        --network)
            CLEAN_ALL=false
            CLEAN_NETWORK=true
            shift
            ;;
        --images)
            CLEAN_ALL=false
            CLEAN_IMAGES=true
            shift
            ;;
        --all)
            CLEAN_ALL=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$CLEAN_ALL" = true ]; then
    CLEAN_CONTAINERS=true
    CLEAN_VOLUMES=true
    CLEAN_NETWORK=true
fi

print_header "xshopai Docker Cleanup"

# =============================================================================
# Remove Containers
# =============================================================================
if [ "$CLEAN_CONTAINERS" = true ]; then
    print_subheader "Removing Containers"
    
    CONTAINERS=$(docker ps -a --filter "name=xshopai-" -q)
    if [ -n "$CONTAINERS" ]; then
        print_step "Stopping containers..."
        echo "$CONTAINERS" | xargs -r docker stop 2>/dev/null || true
        
        print_step "Removing containers..."
        echo "$CONTAINERS" | xargs -r docker rm 2>/dev/null || true
        
        print_success "Containers removed"
    else
        print_info "No xshopai containers found"
    fi
fi

# =============================================================================
# Remove Volumes
# =============================================================================
if [ "$CLEAN_VOLUMES" = true ]; then
    print_subheader "Removing Volumes"
    
    VOLUMES=$(docker volume ls --filter "name=xshopai_" -q)
    if [ -n "$VOLUMES" ]; then
        print_step "Removing volumes..."
        echo "$VOLUMES" | xargs -r docker volume rm 2>/dev/null || true
        print_success "Volumes removed"
    else
        print_info "No xshopai volumes found"
    fi
fi

# =============================================================================
# Remove Network
# =============================================================================
if [ "$CLEAN_NETWORK" = true ]; then
    print_subheader "Removing Network"
    
    if docker network inspect "$DOCKER_NETWORK" &> /dev/null; then
        print_step "Removing network: $DOCKER_NETWORK"
        docker network rm "$DOCKER_NETWORK" 2>/dev/null || true
        print_success "Network removed"
    else
        print_info "Network not found: $DOCKER_NETWORK"
    fi
fi

# =============================================================================
# Remove Images
# =============================================================================
if [ "$CLEAN_IMAGES" = true ]; then
    print_subheader "Removing Images"
    
    IMAGES=$(docker images "xshopai/*" -q)
    if [ -n "$IMAGES" ]; then
        print_step "Removing xshopai images..."
        echo "$IMAGES" | xargs -r docker rmi -f 2>/dev/null || true
        print_success "Images removed"
    else
        print_info "No xshopai images found"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
print_header "Cleanup Complete"

echo -e "${CYAN}Remaining xshopai resources:${NC}"
echo -e "  Containers: $(docker ps -a --filter 'name=xshopai-' -q | wc -l)"
echo -e "  Volumes:    $(docker volume ls --filter 'name=xshopai_' -q | wc -l)"
echo -e "  Images:     $(docker images 'xshopai/*' -q | wc -l)"

print_success "Cleanup completed successfully"
