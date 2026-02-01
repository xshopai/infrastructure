#!/bin/bash

# =============================================================================
# Module 01: Network Setup
# =============================================================================
# Creates the Docker network for xshopai services
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Setting up Docker Network"

# Check Docker
check_docker

# Create network
ensure_network

print_success "Network setup complete"
