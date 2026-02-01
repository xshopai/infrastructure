#!/bin/bash

# =============================================================================
# Module 03: MongoDB Databases
# =============================================================================
# Deploys MongoDB instances for services:
# - product-service (port 27019)
# - user-service (port 27018)
# - auth-service (port 27017)
# - review-service (port 27020)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_header "Deploying MongoDB Databases"

MONGO_IMAGE="mongo:latest"
MONGO_ROOT_USER="${MONGO_ROOT_USER:-admin}"
MONGO_ROOT_PASS="${MONGO_ROOT_PASS:-admin123}"

ensure_image "$MONGO_IMAGE"

# =============================================================================
# MongoDB for Auth Service (port 27017)
# =============================================================================
print_subheader "MongoDB for Auth Service"

AUTH_MONGO_CONTAINER="xshopai-auth-mongodb"
AUTH_MONGO_PORT="27017"
AUTH_MONGO_DB="auth_service_db"

if is_container_running "$AUTH_MONGO_CONTAINER"; then
    print_info "Auth MongoDB is already running"
else
    remove_container "$AUTH_MONGO_CONTAINER"
    
    docker run -d \
        --name "$AUTH_MONGO_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${AUTH_MONGO_PORT}:27017" \
        -e MONGO_INITDB_ROOT_USERNAME="$MONGO_ROOT_USER" \
        -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASS" \
        -e MONGO_INITDB_DATABASE="$AUTH_MONGO_DB" \
        -v xshopai_auth_mongodb_data:/data/db \
        --health-cmd "mongosh --eval 'db.adminCommand(\"ping\")'" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$MONGO_IMAGE"
    
    print_success "Auth MongoDB started on port $AUTH_MONGO_PORT"
fi

# =============================================================================
# MongoDB for User Service (port 27018)
# =============================================================================
print_subheader "MongoDB for User Service"

USER_MONGO_CONTAINER="xshopai-user-mongodb"
USER_MONGO_PORT="27018"
USER_MONGO_DB="user_service_db"

if is_container_running "$USER_MONGO_CONTAINER"; then
    print_info "User MongoDB is already running"
else
    remove_container "$USER_MONGO_CONTAINER"
    
    docker run -d \
        --name "$USER_MONGO_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${USER_MONGO_PORT}:27017" \
        -e MONGO_INITDB_ROOT_USERNAME="$MONGO_ROOT_USER" \
        -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASS" \
        -e MONGO_INITDB_DATABASE="$USER_MONGO_DB" \
        -v xshopai_user_mongodb_data:/data/db \
        --health-cmd "mongosh --eval 'db.adminCommand(\"ping\")'" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$MONGO_IMAGE"
    
    print_success "User MongoDB started on port $USER_MONGO_PORT"
fi

# =============================================================================
# MongoDB for Product Service (port 27019)
# =============================================================================
print_subheader "MongoDB for Product Service"

PRODUCT_MONGO_CONTAINER="xshopai-product-mongodb"
PRODUCT_MONGO_PORT="27019"
PRODUCT_MONGO_DB="product_service_db"

if is_container_running "$PRODUCT_MONGO_CONTAINER"; then
    print_info "Product MongoDB is already running"
else
    remove_container "$PRODUCT_MONGO_CONTAINER"
    
    docker run -d \
        --name "$PRODUCT_MONGO_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${PRODUCT_MONGO_PORT}:27017" \
        -e MONGO_INITDB_ROOT_USERNAME="$MONGO_ROOT_USER" \
        -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASS" \
        -e MONGO_INITDB_DATABASE="$PRODUCT_MONGO_DB" \
        -v xshopai_product_mongodb_data:/data/db \
        --health-cmd "mongosh --eval 'db.adminCommand(\"ping\")'" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$MONGO_IMAGE"
    
    print_success "Product MongoDB started on port $PRODUCT_MONGO_PORT"
fi

# =============================================================================
# MongoDB for Review Service (port 27020)
# =============================================================================
print_subheader "MongoDB for Review Service"

REVIEW_MONGO_CONTAINER="xshopai-review-mongodb"
REVIEW_MONGO_PORT="27020"
REVIEW_MONGO_DB="review_service_db"

if is_container_running "$REVIEW_MONGO_CONTAINER"; then
    print_info "Review MongoDB is already running"
else
    remove_container "$REVIEW_MONGO_CONTAINER"
    
    docker run -d \
        --name "$REVIEW_MONGO_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --restart unless-stopped \
        -p "${REVIEW_MONGO_PORT}:27017" \
        -e MONGO_INITDB_ROOT_USERNAME="$MONGO_ROOT_USER" \
        -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASS" \
        -e MONGO_INITDB_DATABASE="$REVIEW_MONGO_DB" \
        -v xshopai_review_mongodb_data:/data/db \
        --health-cmd "mongosh --eval 'db.adminCommand(\"ping\")'" \
        --health-interval 10s \
        --health-timeout 5s \
        --health-retries 5 \
        "$MONGO_IMAGE"
    
    print_success "Review MongoDB started on port $REVIEW_MONGO_PORT"
fi

# Wait for all MongoDB instances
print_step "Waiting for MongoDB instances to be ready..."
sleep 5

for container in "$AUTH_MONGO_CONTAINER" "$USER_MONGO_CONTAINER" "$PRODUCT_MONGO_CONTAINER" "$REVIEW_MONGO_CONTAINER"; do
    wait_for_container "$container" 30
done

# =============================================================================
# Summary
# =============================================================================
print_header "MongoDB Databases Deployed"

echo -e "\n${CYAN}Connection Strings:${NC}"
echo -e "  Auth:    ${GREEN}mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASS}@localhost:${AUTH_MONGO_PORT}/${AUTH_MONGO_DB}?authSource=admin${NC}"
echo -e "  User:    ${GREEN}mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASS}@localhost:${USER_MONGO_PORT}/${USER_MONGO_DB}?authSource=admin${NC}"
echo -e "  Product: ${GREEN}mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASS}@localhost:${PRODUCT_MONGO_PORT}/${PRODUCT_MONGO_DB}?authSource=admin${NC}"
echo -e "  Review:  ${GREEN}mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASS}@localhost:${REVIEW_MONGO_PORT}/${REVIEW_MONGO_DB}?authSource=admin${NC}"

print_success "MongoDB deployment complete"
