#!/bin/bash

################################################################################
# Azure Service Principal Bootstrap Script
# 
# This script creates the Azure Service Principal needed for GitHub Actions
# to authenticate and deploy resources via Bicep templates.
#
# What this script does:
# 1. Creates Azure Service Principal for GitHub Actions authentication
# 2. Outputs GitHub organization secrets to configure
#
# What Bicep templates handle (NOT this script):
# - Resource Groups
# - Container Registry
# - All other Azure resources
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
# - Azure subscription with Owner or User Access Administrator role
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
DEFAULT_LOCATION="swedencentral"
DEFAULT_ORG_NAME="xshopai"
DEFAULT_PIPELINE="gh"  # Short for GitHub Actions
DEFAULT_TARGET="app-service"  # Deployment target platform

################################################################################
# Main Script
################################################################################

main() {
    log_header "🚀 xshopai Platform - Azure Service Principal Setup"
    
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
    
    local pipeline=$(prompt_input "DevOps platform (gh=GitHub, ado=Azure DevOps)" "$DEFAULT_PIPELINE")
    validate_resource_name "$pipeline" 10 || exit 1
    
    local target=$(prompt_input "Target platform (app-service, aca, aks)" "$DEFAULT_TARGET")
    validate_resource_name "$target" 20 || exit 1
    
    local subscription_id=$current_sub_id
    local tenant_id=$(az account show --query tenantId -o tsv)
    
    # Generate resource names following pattern: {type}-{org}-{platform}-{target}
    local sp_name="sp-${org_name}-${pipeline}-${target}"
    
    echo ""
    log_info "Service Principal to create:"
    echo "  Name: $sp_name"
    echo ""
    log_info "Naming convention: {type}-${org_name}-${pipeline}-${target}"
    log_info "All other resources (RG, ACR, databases, etc.) will be created by Bicep templates."
    echo ""
    
    if ! prompt_confirm "Continue with these settings?"; then
        log_info "Bootstrap cancelled"
        exit 0
    fi
    
    # Create secrets directory
    local secrets_dir="$SCRIPT_DIR/../.secrets"
    mkdir -p "$secrets_dir"
    
    local sp_output_file="$secrets_dir/azure-credentials-${pipeline}.json"
    
    # Step 1: Create Service Principal
    log_header "🔐 Creating Service Principal"
    
    # Check if SP already exists
    local existing_sp_id=$(az ad sp list --display-name "$sp_name" --query '[0].appId' -o tsv 2>/dev/null)
    local should_create=false
    
    if [[ -n "$existing_sp_id" ]]; then
        log_warning "Service Principal '$sp_name' already exists"
        
        if prompt_confirm "Delete and recreate it?"; then
            log_info "Deleting existing Service Principal..."
            if az ad sp delete --id "$existing_sp_id"; then
                log_success "Existing Service Principal deleted"
                
                # Also delete the App Registration if it exists (SP deletion doesn't always remove it)
                local app_id=$(az ad app list --display-name "$sp_name" --query '[0].appId' -o tsv 2>/dev/null)
                if [[ -n "$app_id" ]]; then
                    log_info "Deleting associated App Registration..."
                    az ad app delete --id "$app_id" 2>/dev/null || true
                fi
                
                # Wait for Azure AD to propagate (60 seconds recommended)
                log_info "Waiting 15 seconds for Azure AD propagation..."
                sleep 15
                should_create=true
            else
                log_error "Failed to delete existing Service Principal"
                log_error "You can manually delete it with:"
                log_error "  az ad sp delete --id $existing_sp_id"
                exit 1
            fi
        else
            log_warning "Keeping existing Service Principal"
            if [[ ! -f "$sp_output_file" ]]; then
                log_error "Credentials file not found: $sp_output_file"
                log_error "Either delete the SP and rerun, or manually export credentials"
                exit 1
            fi
            log_info "Using existing credentials from: $sp_output_file"
            should_create=false
        fi
    else
        should_create=true
    fi
    
    # Create SP if needed
    local client_id=""
    local client_secret=""
    
    if [[ "$should_create" == "true" ]]; then
        log_info "Creating Service Principal '$sp_name'..."
        log_warning "This may take a few moments..."
        
        # Capture both stdout and stderr separately
        local sp_error_file="$secrets_dir/sp-error.log"
        local sp_temp_file="$secrets_dir/sp-temp.json"
        
        # Note: MSYS_NO_PATHCONV=1 prevents Git Bash from converting /subscriptions/ to C:/Program Files/Git/subscriptions/
        # This is a known issue with MSYS path conversion on Windows
        if MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
            --name "$sp_name" \
            --role "Contributor" \
            --scopes "/subscriptions/$subscription_id" \
            > "$sp_temp_file" 2> "$sp_error_file"; then
            
            # Extract credentials from new format
            client_id=$(jq -r '.appId' "$sp_temp_file")
            client_secret=$(jq -r '.password' "$sp_temp_file")
            local tenant=$(jq -r '.tenant' "$sp_temp_file")
            
            # Build the AZURE_CREDENTIALS JSON format (for backward compatibility)
            cat > "$sp_output_file" << EOF
{
    "clientId": "$client_id",
    "clientSecret": "$client_secret",
    "subscriptionId": "$subscription_id",
    "tenantId": "$tenant",
    "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
    "resourceManagerEndpointUrl": "https://management.azure.com/",
    "activeDirectoryGraphResourceId": "https://graph.windows.net/",
    "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
    "galleryEndpointUrl": "https://gallery.azure.com/",
    "managementEndpointUrl": "https://management.core.windows.net/"
}
EOF
            
            rm -f "$sp_temp_file"
            log_success "Service Principal created successfully"
            log_warning "Credentials saved to: $sp_output_file"
            log_warning "⚠️  DO NOT COMMIT THIS FILE TO VERSION CONTROL!"
            rm -f "$sp_error_file"
        else
            log_error "Failed to create Service Principal"
            log_error "Azure CLI error:"
            cat "$sp_error_file" | while read line; do
                echo -e "  ${RED}$line${NC}"
            done
            echo ""
            log_info "Common causes:"
            echo "  - Insufficient Azure AD permissions (need Application Administrator role)"
            echo "  - SP app registration already exists (try different name)"
            echo "  - Subscription scope invalid"
            echo ""
            log_info "Manual command to try:"
            echo "  az ad sp create-for-rbac --name \"$sp_name\" --role Contributor --scopes \"/subscriptions/$subscription_id\""
            rm -f "$sp_error_file" "$sp_temp_file"
            exit 1
        fi
    fi
    
    # Extract credentials from file
    client_id=$(jq -r '.clientId' "$sp_output_file")
    client_secret=$(jq -r '.clientSecret' "$sp_output_file")
    
    # Step 2: Output GitHub Secrets
    log_header "🔑 GitHub Organization Secrets"
    
    local secrets_file="$secrets_dir/github-secrets-${pipeline}.txt"
    
    cat > "$secrets_file" << EOF
# GitHub Organization Secrets for ${org_name}
# Add these secrets at: https://github.com/organizations/${org_name}/settings/secrets/actions

# Azure Authentication (used by all workflows)
AZURE_CLIENT_ID=$client_id
AZURE_CLIENT_SECRET=$client_secret
AZURE_TENANT_ID=$tenant_id
AZURE_SUBSCRIPTION_ID=$subscription_id

# Legacy format (AZURE_CREDENTIALS) - may be required by some actions
AZURE_CREDENTIALS=$(cat "$sp_output_file")
EOF
    
    log_success "GitHub secrets configuration saved to: $secrets_file"
    echo ""
    
    # Display the secrets for manual copying
    log_header "📋 GitHub Organization Secrets to Configure"
    echo ""
    echo -e "${YELLOW}Go to: https://github.com/organizations/${org_name}/settings/secrets/actions${NC}"
    echo ""
    echo -e "${BLUE}Create these organization secrets:${NC}"
    echo ""
    
    echo -e "${GREEN}1. AZURE_CLIENT_ID${NC}"
    echo "   Value: $client_id"
    echo ""
    
    echo -e "${GREEN}2. AZURE_CLIENT_SECRET${NC}"
    echo "   Value: $client_secret"
    echo ""
    
    echo -e "${GREEN}3. AZURE_TENANT_ID${NC}"
    echo "   Value: $tenant_id"
    echo ""
    
    echo -e "${GREEN}4. AZURE_SUBSCRIPTION_ID${NC}"
    echo "   Value: $subscription_id"
    echo ""
    
    # Offer to set secrets via GitHub CLI
    if [ "$has_github_cli" = true ]; then
        echo ""
        if prompt_confirm "Do you want to automatically add these secrets using GitHub CLI?"; then
            add_secrets_via_gh_cli "$org_name" "$client_id" "$client_secret" "$tenant_id" "$subscription_id"
        fi
    fi
    
    # Display next steps
    display_next_steps "$org_name" "$pipeline" "$target"
    
    log_success "Bootstrap complete! 🎉"
    echo ""
    log_warning "Remember: The .secrets/ folder is in .gitignore - do not commit it!"
}

################################################################################
# Add secrets via GitHub CLI
################################################################################

add_secrets_via_gh_cli() {
    local org_name=$1
    local client_id=$2
    local client_secret=$3
    local tenant_id=$4
    local subscription_id=$5
    
    log_header "🔧 Adding Secrets via GitHub CLI"
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log_warning "Not authenticated with GitHub CLI. Please run 'gh auth login' first."
        return 1
    fi
    
    log_info "Adding secrets to organization: $org_name"
    
    # Add each secret
    echo "$client_id" | gh secret set AZURE_CLIENT_ID --org "$org_name" --visibility all
    log_success "Added AZURE_CLIENT_ID"
    
    echo "$client_secret" | gh secret set AZURE_CLIENT_SECRET --org "$org_name" --visibility all
    log_success "Added AZURE_CLIENT_SECRET"
    
    echo "$tenant_id" | gh secret set AZURE_TENANT_ID --org "$org_name" --visibility all
    log_success "Added AZURE_TENANT_ID"
    
    echo "$subscription_id" | gh secret set AZURE_SUBSCRIPTION_ID --org "$org_name" --visibility all
    log_success "Added AZURE_SUBSCRIPTION_ID"
    
    log_success "All secrets added successfully!"
}

################################################################################
# Display next steps
################################################################################

display_next_steps() {
    local org_name=$1
    local pipeline=$2
    local target=$3
    
    log_header "📋 Next Steps"
    echo ""
    echo -e "${BLUE}1. Add the GitHub organization secrets listed above${NC}"
    echo "   URL: https://github.com/organizations/${org_name}/settings/secrets/actions"
    echo ""
    echo -e "${BLUE}2. Configure GitHub Environments${NC}"
    echo "   Run: ./github-setup.sh"
    echo "   This creates 'development' and 'production' environments with protection rules"
    echo ""
    echo -e "${BLUE}3. Deploy Infrastructure (creates all Azure resources via Bicep)${NC}"
    echo "   Go to: https://github.com/${org_name}/infrastructure/actions"
    echo "   Run: 'Deploy App Service Infrastructure' workflow"
    echo "   Select environment: development"
    echo ""
    echo "   This will create all Azure resources:"
    echo "   - Resource Group (rg-${org_name}-${pipeline}-development)"
    echo "   - Container Registry, Key Vault, Databases"
    echo "   - App Services, Redis, RabbitMQ, etc."
    echo ""
    echo -e "${BLUE}4. Build and Deploy Services${NC}"
    echo "   After infrastructure is ready, trigger service deployment workflows"
    echo ""
    echo -e "${YELLOW}For detailed instructions, see: azure/app-service/docs/README.md${NC}"
    echo ""
}

################################################################################
# Run main function
################################################################################

main "$@"
