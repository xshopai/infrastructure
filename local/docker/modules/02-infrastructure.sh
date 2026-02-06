#!/bin/bash

# =============================================================================
# Module 02: Infrastructure Services (RabbitMQ, Mailpit)
# =============================================================================
# Deploys shared infrastructure services:
# - RabbitMQ (Message Broker)
# - Mailpit (Email Testing)
#
# Note: Redis and Zipkin are managed by Dapr (dapr init)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying Infrastructure Services"

# =============================================================================
# RabbitMQ (Message Broker)
# =============================================================================
print_subheader "RabbitMQ Message Broker"

RABBITMQ_CONTAINER="xshopai-rabbitmq"
RABBITMQ_IMAGE="rabbitmq:3-management"
RABBITMQ_PORT="5672"
RABBITMQ_MGMT_PORT="15672"
RABBITMQ_USER="${RABBITMQ_USER:-admin}"
RABBITMQ_PASS="${RABBITMQ_PASS:-admin123}"

ensure_image "$RABBITMQ_IMAGE"

if is_container_running "$RABBITMQ_CONTAINER"; then
    print_info "RabbitMQ is already running"
else
    remove_container "$RABBITMQ_CONTAINER"
    
    docker run -d \
        --name "$RABBITMQ_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${RABBITMQ_PORT}:5672" \
        -p "${RABBITMQ_MGMT_PORT}:15672" \
        -e RABBITMQ_DEFAULT_USER="$RABBITMQ_USER" \
        -e RABBITMQ_DEFAULT_PASS="$RABBITMQ_PASS" \
        -v xshopai_rabbitmq_data:/var/lib/rabbitmq \
        --health-cmd "rabbitmq-diagnostics ping" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$RABBITMQ_IMAGE"
    
    print_success "RabbitMQ started"
fi

wait_for_container "$RABBITMQ_CONTAINER" 60

# =============================================================================
# Mailpit (Email Testing)
# =============================================================================
print_subheader "Mailpit Email Testing Server"

MAILPIT_CONTAINER="xshopai-mailpit"
MAILPIT_IMAGE="axllent/mailpit:latest"
MAILPIT_SMTP_PORT="1025"
MAILPIT_UI_PORT="8025"

ensure_image "$MAILPIT_IMAGE"

if is_container_running "$MAILPIT_CONTAINER"; then
    print_info "Mailpit is already running"
else
    remove_container "$MAILPIT_CONTAINER"
    
    docker run -d \
        --name "$MAILPIT_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${MAILPIT_SMTP_PORT}:1025" \
        -p "${MAILPIT_UI_PORT}:8025" \
        -e MP_MAX_MESSAGES=5000 \
        -e MP_SMTP_AUTH_ACCEPT_ANY=1 \
        -e MP_SMTP_AUTH_ALLOW_INSECURE=1 \
        --health-cmd "wget --spider -q http://localhost:8025/ || exit 1" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 3 \
        "$MAILPIT_IMAGE"
    
    print_success "Mailpit started"
fi

wait_for_container "$MAILPIT_CONTAINER" 30

# =============================================================================
# Summary
# =============================================================================
print_header "Infrastructure Services Deployed"

echo -e "\n${CYAN}Service URLs:${NC}"
echo -e "  RabbitMQ Management:  ${GREEN}http://localhost:${RABBITMQ_MGMT_PORT}${NC} (${RABBITMQ_USER}/${RABBITMQ_PASS})"
echo -e "  Redis (Dapr):         ${GREEN}localhost:6379${NC} (managed by dapr init)"
echo -e "  Zipkin (Dapr):        ${GREEN}http://localhost:9411${NC} (managed by dapr init)"
echo -e "  Mailpit UI:           ${GREEN}http://localhost:${MAILPIT_UI_PORT}${NC}"

echo -e "\n${YELLOW}Note:${NC} Redis and Zipkin are managed by Dapr. Run 'dapr init' to create dapr_redis and dapr_zipkin containers."

print_success "Infrastructure deployment complete"
