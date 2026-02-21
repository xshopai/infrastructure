#!/bin/bash
# =============================================================================
# RabbitMQ Container Instance Module
# =============================================================================

deploy_rabbitmq() {
    print_header "Creating RabbitMQ Container Instance"
    
    validate_required_vars "RABBITMQ_INSTANCE" "RESOURCE_GROUP" "LOCATION" || return 1
    
    export RABBITMQ_USER="${RABBITMQ_USER:-admin}"
    
    # Check if container instance exists - skip quickly
    if az container show --name "$RABBITMQ_INSTANCE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "RabbitMQ exists: $RABBITMQ_INSTANCE (skipping creation)"
        
        # Try to retrieve password from Key Vault (from previous deployment)
        if [ -n "$KEY_VAULT" ] && az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
            local stored_password=$(az keyvault secret show --vault-name "$KEY_VAULT" --name "rabbitmq-password" --query value -o tsv 2>/dev/null || echo "")
            if [ -n "$stored_password" ]; then
                export RABBITMQ_PASSWORD="$stored_password"
                print_info "Retrieved RabbitMQ password from Key Vault"
            fi
        fi
        # If no password from KV and not already set, generate (won't match container - will be stored in KV for next run)
        export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(generate_password)}"
    else
        # New container - generate password
        export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(generate_password)}"
        print_info "Creating RabbitMQ: $RABBITMQ_INSTANCE"

        # Use MCR mirror of Docker Hub to avoid rate limiting from Azure
        local rabbitmq_image="mcr.microsoft.com/mirror/docker/library/rabbitmq:3-management"

        if az container create \
            --name "$RABBITMQ_INSTANCE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --image "$rabbitmq_image" \
            --cpu 1 \
            --memory 1.5 \
            --ports 5672 15672 \
            --ip-address Public \
            --dns-name-label "$RABBITMQ_INSTANCE" \
            --environment-variables \
                RABBITMQ_DEFAULT_USER="$RABBITMQ_USER" \
                RABBITMQ_DEFAULT_PASS="$RABBITMQ_PASSWORD" \
            --output none; then
            print_success "RabbitMQ created: $RABBITMQ_INSTANCE"
        else
            print_error "Failed to create RabbitMQ"
            return 1
        fi
        
        # Wait for container to be running
        print_info "Waiting for RabbitMQ to start..."
        local MAX_ATTEMPTS=30
        local ATTEMPT=0
        
        while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
            local STATE=$(az container show \
                --name "$RABBITMQ_INSTANCE" \
                --resource-group "$RESOURCE_GROUP" \
                --query "instanceView.state" -o tsv 2>/dev/null)
            
            if [ "$STATE" = "Running" ]; then
                print_success "RabbitMQ is running"
                break
            fi
            
            ATTEMPT=$((ATTEMPT + 1))
            echo -n "."
            sleep 10
        done
        echo ""
    fi
    
    # Get RabbitMQ FQDN
    export RABBITMQ_FQDN=$(az container show \
        --name "$RABBITMQ_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "ipAddress.fqdn" -o tsv)
    
    export RABBITMQ_HOST="${RABBITMQ_FQDN}"
    export RABBITMQ_CONNECTION="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_FQDN}:5672"
    export RABBITMQ_MANAGEMENT_URL="http://${RABBITMQ_FQDN}:15672"
    export RABBITMQ_USER
    export RABBITMQ_PASSWORD
    
    print_success "RabbitMQ configured"
    print_info "RabbitMQ Host: $RABBITMQ_HOST"
    print_info "Management UI: $RABBITMQ_MANAGEMENT_URL"
}
