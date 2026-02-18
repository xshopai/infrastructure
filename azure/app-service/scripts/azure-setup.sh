#!/bin/bash

################################################################################
# Azure App Service Bootstrap Script
# 
# This script sets up the Azure infrastructure prerequisites for deploying
# the xshopai platform to Azure App Service using GitHub Actions.
#
# What this script does:
# 1. Creates Azure Service Principal for GitHub Actions authentication
# 2. Creates shared Azure Container Registry (ACR)
# 3. Outputs GitHub organization secrets to configure
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
# - Azure subscription with Owner or Contributor role
# - GitHub organization admin access (to add secrets)
#
# Usage:
#   ./azure-setup.sh
#
################################################################################

set -e  # Exit on error

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
DEFAULT_LOCATION="eastus"
DEFAULT_ORG_NAME="xshopai"
DEFAULT_PIPELINE="github-actions"

################################################################################
# Main Script
################################################################################

main() {
    log_header "🚀 xshopai Platform - Azure App Service Bootstrap"
    
    # Check prerequisites
    check_azure_cli
    check_azure_login
    
    local has_github_cli=false
    if check_github_cli; then
        has_github_cli=true
    fi
    
    # Get current subscription info
    local current_sub_id=$(get_current_subscription)
    local current_sub_name=$(get_current_subscription_name)
    
    log_info "Current Azure Subscription: $current_sub_name"
    log_info "Subscription ID: $current_sub_id"
    echo ""
    
    if ! prompt_confirm "Do you want to use this subscription?"; then
        log_info "Please run 'az account set --subscription <subscription-id>' to switch subscriptions"
        exit 0
    fi
    
    # Collect input
    log_header "📝 Configuration"
    
    local org_name=$(prompt_input "GitHub Organization name" "$DEFAULT_ORG_NAME")
    validate_resource_name "$org_name" 20 || exit 1
    
    local pipeline=$(prompt_input "Pipeline identifier (github-actions or azure-devops)" "$DEFAULT_PIPELINE")
    validate_resource_name "$pipeline" 30 || exit 1
    
    local location=$(prompt_input "Azure region" "$DEFAULT_LOCATION")
    
    local subscription_id=$current_sub_id
    
    # Generate resource names
    local sp_name="sp-${org_name}-${pipeline}"
    local shared_rg_name="rg-${org_name}-shared"
    local acr_name="acr${org_name}"  # ACR names can't have hyphens
    
    echo ""
    log_info "The following resources will be created:"
    echo "  Service Principal: $sp_name"
    echo "  Resource Group:    $shared_rg_name"
    echo "  Container Registry: $acr_name"
    echo "  Location:          $location"
    echo ""
    
    if ! prompt_confirm "Continue with these settings?"; then
        log_info "Bootstrap cancelled"
        exit 0
    fi
    
    # Step 1: Create Service Principal
    log_header "🔐 Step 1: Creating Service Principal"
    
    local sp_output_file="$SCRIPT_DIR/../.secrets/azure-credentials-${pipeline}.json"
    mkdir -p "$(dirname "$sp_output_file")"
    
    log_info "Creating Service Principal '$sp_name'..."
    log_warning "This may take a few moments..."
    
    if az ad sp create-for-rbac \
        --name "$sp_name" \
        --role "Contributor" \
        --scopes "/subscriptions/$subscription_id" \
        --sdk-auth \
        > "$sp_output_file" 2>&1; then
        
        log_success "Service Principal created successfully"
        log_warning "Credentials saved to: $sp_output_file"
        log_warning "⚠️  DO NOT COMMIT THIS FILE TO VERSION CONTROL!"
    else
        log_error "Failed to create Service Principal"
        log_error "You may need to delete an existing SP with the same name first:"
        log_error "  az ad sp delete --id \$(az ad sp list --display-name '$sp_name' --query '[0].appId' -o tsv)"
        exit 1
    fi
    
    # Step 2: Create Shared Resource Group
    log_header "📦 Step 2: Creating Shared Resource Group"
    
    create_resource_group_if_not_exists "$shared_rg_name" "$location" || exit 1
    
    # Step 3: Create Azure Container Registry
    log_header "🐳 Step 3: Creating Azure Container Registry"
    
    if az acr show --name "$acr_name" --resource-group "$shared_rg_name" &> /dev/null; then
        log_info "Container Registry '$acr_name' already exists"
    else
        log_info "Creating Container Registry '$acr_name'..."
        if az acr create \
            --name "$acr_name" \
            --resource-group "$shared_rg_name" \
            --sku "Standard" \
            --location "$location" \
            --admin-enabled true \
            --output none; then
            log_success "Container Registry created"
        else
            log_error "Failed to create Container Registry"
            exit 1
        fi
    fi
    
    # Get ACR credentials
    log_info "Retrieving ACR credentials..."
    local acr_login_server=$(az acr show --name "$acr_name" --query loginServer -o tsv)
    local acr_username=$(az acr credential show --name "$acr_name" --query username -o tsv)
    local acr_password=$(az acr credential show --name "$acr_name" --query "passwords[0].value" -o tsv)
    
    # Step 4: Output GitHub Secrets
    log_header "🔑 Step 4: GitHub Organization Secrets"
    
    local secrets_file="$SCRIPT_DIR/../.secrets/github-secrets-${pipeline}.txt"
    
    cat > "$secrets_file" << EOF
# GitHub Organization Secrets for ${org_name}
# Add these secrets at: https://github.com/organizations/${org_name}/settings/secrets/actions

# Azure Authentication
AZURE_CREDENTIALS=$(cat "$sp_output_file")
AZURE_SUBSCRIPTION_ID=$subscription_id
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

# Azure Container Registry
AZURE_ACR_LOGIN_SERVER=$acr_login_server
AZURE_ACR_USERNAME=$acr_username
AZURE_ACR_PASSWORD=$acr_password
EOF
    
    log_success "GitHub secrets configuration saved to: $secrets_file"
    echo ""
    
    # Display the secrets for manual copying
    echo ""
    log_header "📋 GitHub Organization Secrets to Configure"
    echo ""
    echo -e "${YELLOW}Go to: https://github.com/organizations/${org_name}/settings/secrets/actions${NC}"
    echo ""
    echo -e "${BLUE}Create these organization secrets:${NC}"
    echo ""
    
    echo -e "${GREEN}1. AZURE_CREDENTIALS${NC}"
    echo "   Value: (paste entire content from $sp_output_file)"
    echo ""
    
    echo -e "${GREEN}2. AZURE_SUBSCRIPTION_ID${NC}"
    echo "   Value: $subscription_id"
    echo ""
    
    echo -e "${GREEN}3. AZURE_TENANT_ID${NC}"
    echo "   Value: $(az account show --query tenantId -o tsv)"
    echo ""
    
    echo -e "${GREEN}4. AZURE_ACR_LOGIN_SERVER${NC}"
    echo "   Value: $acr_login_server"
    echo ""
    
    echo -e "${GREEN}5. AZURE_ACR_USERNAME${NC}"
    echo "   Value: $acr_username"
    echo ""
    
    echo -e "${GREEN}6. AZURE_ACR_PASSWORD${NC}"
    echo "   Value: $acr_password"
    echo ""
    
    # Offer to set secrets via GitHub CLI
    if [ "$has_github_cli" = true ]; then
        echo ""
        if prompt_confirm "Do you want to automatically add these secrets using GitHub CLI?"; then
            add_secrets_via_gh_cli "$org_name" "$subscription_id" "$sp_output_file" \
                "$acr_login_server" "$acr_username" "$acr_password"
        fi
    fi
    
    # Display next steps
    local next_steps="
1. Add the GitHub organization secrets listed above

2. Configure GitHub Environments in each service repository:
   - Create 'development' environment (no protection rules)
   - Create 'production' environment with:
     * Required reviewers: 2 from 'platform-admins' team
     * Wait timer: 30 minutes
     * Branch restriction: main only

3. Add environment-specific secrets to each service repository:
   For 'development' environment:
     - RESOURCE_GROUP: rg-${org_name}-gh-dev
     - KEY_VAULT_NAME: kv-${org_name}-gh-dev
   
   For 'production' environment:
     - RESOURCE_GROUP: rg-${org_name}-gh-prod
     - KEY_VAULT_NAME: kv-${org_name}-gh-prod

4. Run infrastructure deployment workflow:
   Go to: https://github.com/${org_name}/infrastructure/actions
   Trigger: 'Deploy Infrastructure' workflow
   Select environment: development (to start)

5. After infrastructure is deployed, trigger service deployment workflows
   
For detailed instructions, see: deployment/azure/app-service/docs/README.md
"
    display_next_steps "$next_steps"
    
    log_success "Bootstrap complete! 🎉"
    echo ""
    log_warning "Remember: The .secrets/ folder is in .gitignore - do not commit it!"
}

################################################################################
# Add secrets via GitHub CLI
################################################################################

add_secrets_via_gh_cli() {
    local org_name=$1
    local subscription_id=$2
    local sp_file=$3
    local acr_server=$4
    local acr_user=$5
    local acr_pass=$6
    
    log_header "🔧 Adding Secrets via GitHub CLI"
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log_warning "Not authenticated with GitHub CLI. Please run 'gh auth login' first."
        return 1
    fi
    
    log_info "Adding secrets to organization: $org_name"
    
    # Add each secret
    echo "$subscription_id" | gh secret set AZURE_SUBSCRIPTION_ID --org "$org_name" --visibility all
    log_success "Added AZURE_SUBSCRIPTION_ID"
    
    az account show --query tenantId -o tsv | gh secret set AZURE_TENANT_ID --org "$org_name" --visibility all
    log_success "Added AZURE_TENANT_ID"
    
    cat "$sp_file" | gh secret set AZURE_CREDENTIALS --org "$org_name" --visibility all
    log_success "Added AZURE_CREDENTIALS"
    
    echo "$acr_server" | gh secret set AZURE_ACR_LOGIN_SERVER --org "$org_name" --visibility all
    log_success "Added AZURE_ACR_LOGIN_SERVER"
    
    echo "$acr_user" | gh secret set AZURE_ACR_USERNAME --org "$org_name" --visibility all
    log_success "Added AZURE_ACR_USERNAME"
    
    echo "$acr_pass" | gh secret set AZURE_ACR_PASSWORD --org "$org_name" --visibility all
    log_success "Added AZURE_ACR_PASSWORD"
    
    log_success "All secrets added successfully!"
}

################################################################################
# Run main function
################################################################################

main "$@"
