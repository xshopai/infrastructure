#!/bin/bash
# =============================================================================
# Azure OpenAI Deployment Module
# =============================================================================
# Creates an Azure OpenAI Cognitive Services account and deploys a gpt-4o
# model. This must run BEFORE 10-keyvault.sh so the endpoint and key are
# available for secret storage.
#
# gpt-4o is available in francecentral (platform default) but the script
# probes that region first, then falls back through a prioritised list of
# European and US regions in case quota is exhausted or the SKU is unavailable.
#
# Exports:
#   AZURE_OPENAI_NAME     - Resource name
#   AZURE_OPENAI_ENDPOINT - HTTPS endpoint (https://<name>.openai.azure.com/)
#   AZURE_OPENAI_API_KEY  - Primary access key
#   OPENAI_LOCATION       - Region where the resource was created
# =============================================================================

set -e

deploy_azure_openai() {
    print_header "Creating Azure OpenAI Resource"

    validate_required_vars "RESOURCE_GROUP" "PROJECT_NAME" "SHORT_ENV" "SUFFIX" || return 1

    local openai_name="oai-${PROJECT_NAME}-${SHORT_ENV}-${SUFFIX}"
    local deployment_name="${AZURE_OPENAI_DEPLOYMENT_NAME:-gpt-4o}"
    local model_version="2024-11-20"  # Latest stable GA version of gpt-4o

    # -------------------------------------------------------------------------
    # Region selection
    # Try $LOCATION first (francecentral by default — gpt-4o is available there).
    # Fall back through European-first list in case of quota/capacity issues.
    # -------------------------------------------------------------------------
    local candidate_regions=("$LOCATION" "swedencentral" "westeurope" "germanywestcentral" "uksouth" "eastus2")
    local openai_location=""

    for region in "${candidate_regions[@]}"; do
        # Avoid duplicate check if a fallback region equals $LOCATION
        [[ -z "$region" ]] && continue
        print_info "Checking Azure OpenAI availability in: $region"
        if az cognitiveservices account list-skus \
            --kind OpenAI \
            --location "$region" \
            --query "[?name=='S0'] | length(@)" \
            --output tsv 2>/dev/null | grep -qv "^0$"; then
            openai_location="$region"
            break
        fi
    done

    if [ -z "$openai_location" ]; then
        print_error "Azure OpenAI (S0 SKU) not available in any candidate region"
        print_error "Checked: ${candidate_regions[*]}"
        return 1
    fi

    if [ "$openai_location" != "$LOCATION" ]; then
        print_warning "Azure OpenAI not available in $LOCATION — using: $openai_location"
    else
        print_info "Azure OpenAI will be deployed to: $openai_location"
    fi

    export OPENAI_LOCATION="$openai_location"

    # -------------------------------------------------------------------------
    # Create Cognitive Services account (kind = OpenAI)
    # -------------------------------------------------------------------------
    if az cognitiveservices account show \
        --name "$openai_name" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "Azure OpenAI account exists: $openai_name (skipping creation)"
    else
        print_info "Creating Azure OpenAI account: $openai_name"
        if az cognitiveservices account create \
            --name "$openai_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$openai_location" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "$openai_name" \
            --output none; then
            print_success "Azure OpenAI account created: $openai_name"
        else
            print_error "Failed to create Azure OpenAI account: $openai_name"
            return 1
        fi
    fi

    # -------------------------------------------------------------------------
    # Deploy gpt-4o model
    # -------------------------------------------------------------------------
    if az cognitiveservices account deployment show \
        --name "$openai_name" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$deployment_name" &>/dev/null; then
        print_success "Model deployment exists: $deployment_name (skipping)"
    else
        print_info "Deploying model: $deployment_name (version $model_version)..."
        if az cognitiveservices account deployment create \
            --name "$openai_name" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$deployment_name" \
            --model-name "gpt-4o" \
            --model-version "$model_version" \
            --model-format OpenAI \
            --sku-name "Standard" \
            --sku-capacity 10 \
            --output none; then
            print_success "Model deployed: $deployment_name"
        else
            print_error "Failed to deploy model: $deployment_name"
            return 1
        fi
    fi

    # -------------------------------------------------------------------------
    # Export connection details (consumed by 10-keyvault.sh)
    # -------------------------------------------------------------------------
    export AZURE_OPENAI_NAME="$openai_name"
    export AZURE_OPENAI_ENDPOINT="https://${openai_name}.openai.azure.com/"
    export AZURE_OPENAI_API_KEY=$(az cognitiveservices account keys list \
        --name "$openai_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv 2>/dev/null || echo "")

    if [ -z "$AZURE_OPENAI_API_KEY" ]; then
        print_error "Failed to retrieve Azure OpenAI API key for: $openai_name"
        return 1
    fi

    print_info "OpenAI Resource:  $openai_name"
    print_info "OpenAI Region:    $openai_location"
    print_info "OpenAI Endpoint:  $AZURE_OPENAI_ENDPOINT"
    print_info "Model Deployment: $deployment_name ($model_version)"
    print_success "Azure OpenAI configured"

    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_azure_openai
fi
