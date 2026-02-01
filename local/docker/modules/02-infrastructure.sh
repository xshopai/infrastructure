#!/bin/bash

# =============================================================================
# Module 02: Infrastructure Services (RabbitMQ, Redis, Observability)
# =============================================================================
# Deploys shared infrastructure services:
# - RabbitMQ (Message Broker)
# - Redis (Cache/State Store for Dapr)
# - Jaeger (Distributed Tracing)
# - Mailpit (Email Testing)
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
# Redis (Cache/State Store)
# =============================================================================
print_subheader "Redis Cache/State Store"

REDIS_CONTAINER="xshopai-redis"
REDIS_IMAGE="redis:7-alpine"
REDIS_PORT="6379"
REDIS_PASSWORD="${REDIS_PASSWORD:-redis123}"

ensure_image "$REDIS_IMAGE"

if is_container_running "$REDIS_CONTAINER"; then
    print_info "Redis is already running"
else
    remove_container "$REDIS_CONTAINER"
    
    docker run -d \
        --name "$REDIS_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${REDIS_PORT}:6379" \
        -v xshopai_redis_data:/data \
        --health-cmd "redis-cli ping | grep PONG" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$REDIS_IMAGE" \
        redis-server --appendonly yes --requirepass "$REDIS_PASSWORD"
    
    print_success "Redis started"
fi

wait_for_container "$REDIS_CONTAINER" 30

# =============================================================================
# Jaeger (Distributed Tracing)
# =============================================================================
print_subheader "Jaeger Distributed Tracing"

JAEGER_CONTAINER="xshopai-jaeger"
JAEGER_IMAGE="jaegertracing/all-in-one:latest"
JAEGER_UI_PORT="16686"
JAEGER_COLLECTOR_HTTP="14268"
JAEGER_COLLECTOR_GRPC="14250"
JAEGER_OTLP_HTTP="4318"
JAEGER_OTLP_GRPC="4317"

ensure_image "$JAEGER_IMAGE"

if is_container_running "$JAEGER_CONTAINER"; then
    print_info "Jaeger is already running"
else
    remove_container "$JAEGER_CONTAINER"
    
    docker run -d \
        --name "$JAEGER_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${JAEGER_UI_PORT}:16686" \
        -p "${JAEGER_COLLECTOR_HTTP}:14268" \
        -p "${JAEGER_COLLECTOR_GRPC}:14250" \
        -p "${JAEGER_OTLP_HTTP}:4318" \
        -p "${JAEGER_OTLP_GRPC}:4317" \
        -e COLLECTOR_OTLP_ENABLED=true \
        --health-cmd "wget --spider -q http://localhost:16686/ || exit 1" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 3 \
        "$JAEGER_IMAGE"
    
    print_success "Jaeger started"
fi

wait_for_container "$JAEGER_CONTAINER" 30

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
echo -e "  Redis:                ${GREEN}localhost:${REDIS_PORT}${NC} (password: ${REDIS_PASSWORD})"
echo -e "  Jaeger UI:            ${GREEN}http://localhost:${JAEGER_UI_PORT}${NC}"
echo -e "  Mailpit UI:           ${GREEN}http://localhost:${MAILPIT_UI_PORT}${NC}"

print_success "Infrastructure deployment complete"
