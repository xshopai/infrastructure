#!/bin/bash

################################################################################
# xshopai Platform - One-Click Deployment to Azure App Service
#
# This master script orchestrates the complete setup process:
# 1. Authenticates to Azure and GitHub
# 2. Creates Azure Service Principal for GitHub Actions
# 3. Configures GitHub organization secrets automatically
# 4. Creates GitHub environments in all service repositories
# 5. Offers to trigger infrastructure deployment
# 6. Provides verification and next steps
#
# Note: Resource Group, ACR, and all other Azure resources are created
# by the Bicep templates - NOT by this script.
#
# Goal: Turn a fresh clone into a fully configured deployment in minutes.
#
# Prerequisites:
#   - Azure CLI installed (az)
#   - GitHub CLI installed (gh) - will auto-install secrets if available
#   - Git installed
#
# Usage:
#   cd infrastructure/azure/app-service
#   ./scripts/deploy.sh
#
################################################################################

set -e  # Exit on error

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
DEFAULT_ORG_NAME="xshopai"
DEFAULT_LOCATION="swedencentral"
DEFAULT_PIPELINE="gh"  # Short identifier for GitHub Actions

################################################################################
# Check All Prerequisites
################################################################################

check_prerequisites() {
    log_header "🔍 Checking Prerequisites"
    
    local all_good=true
    
    # Check Azure CLI
    if command -v az &> /dev/null; then
        log_success "Azure CLI: $(az version --query '"azure-cli"' -o tsv)"
    else
        log_error "Azure CLI not installed"
        log_info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        all_good=false
    fi
    
    # Check GitHub CLI
    if command -v gh &> /dev/null; then
        log_success "GitHub CLI: $(gh --version | head -n1)"
        HAS_GH_CLI=true
    else
        log_warning "GitHub CLI not installed (optional but recommended)"
        log_info "Install from: https://cli.github.com/"
        log_info "Without it, you'll need to manually add GitHub secrets"
        HAS_GH_CLI=false
    fi
    
    # Check Git
    if command -v git &> /dev/null; then
        log_success "Git: $(git --version | cut -d' ' -f3)"
    else
        log_error "Git not installed"
        all_good=false
    fi
    
    if [ "$all_good" = false ]; then
        log_error "Please install missing prerequisites and try again"
        exit 1
    fi
    
    echo ""
}

################################################################################
# Authenticate to Azure
################################################################################

auth_azure() {
    log_header "🔐 Azure Authentication"
    
    if az account show &> /dev/null; then
        local sub_name=$(az account show --query name -o tsv)
        local sub_id=$(az account show --query id -o tsv)
        log_success "Already logged into Azure"
        log_info "Subscription: $sub_name"
        log_info "Subscription ID: $sub_id"
        echo ""
        
        if ! prompt_confirm "Use this subscription?"; then
            log_info "Please run 'az account set --subscription <id>' to switch"
            log_info "Then re-run this script"
            exit 0
        fi
    else
        log_info "Please log into Azure..."
        az login
        log_success "Azure login successful"
    fi
    
    echo ""
}

################################################################################
# Authenticate to GitHub
################################################################################

auth_github() {
    log_header "🔐 GitHub Authentication"
    
    if [ "$HAS_GH_CLI" = false ]; then
        log_warning "GitHub CLI not installed - skipping auto-configuration"
        log_info "You'll need to manually add secrets to GitHub organization"
        echo ""
        return 0
    fi
    
    # Check if GH_TOKEN is set (common in CI/CD and automation)
    if [ -n "${GH_TOKEN:-}" ]; then
        log_success "Using GH_TOKEN for authentication"
        log_info "GitHub CLI will use the token from environment variable"
        echo ""
        return 0
    fi
    
    if gh auth status &> /dev/null; then
        log_success "Already authenticated to GitHub"
        gh auth status 2>&1 | grep "Logged in" || true
    else
        log_info "Authenticating to GitHub..."
        log_info "You'll be asked to authenticate via browser or token"
        echo ""
        gh auth login
        log_success "GitHub authentication successful"
    fi
    
    echo ""
}

################################################################################
# Run Bootstrap (Service Principal Setup)
################################################################################

run_bootstrap() {
    log_header "🚀 Azure Service Principal Setup"
    log_info "Creating Service Principal for GitHub Actions authentication..."
    echo ""
    
    # Make azure-setup script executable
    chmod +x "$SCRIPT_DIR/azure-setup.sh"
    
    # Run Azure setup
    if "$SCRIPT_DIR/azure-setup.sh"; then
        log_success "Azure setup completed successfully"
        return 0
    else
        log_error "Azure setup failed"
        return 1
    fi
}

################################################################################
# Setup GitHub Environments (via GitHub API)
################################################################################

setup_github_environments() {
    log_header "🌍 Setting Up GitHub Environments"
    
    if [ "$HAS_GH_CLI" = false ]; then
        log_warning "GitHub CLI not available - skipping environment creation"
        log_info "You can manually create environments later following the docs"
        echo ""
        return 0
    fi
    
    log_info "Creating 'development' and 'production' environments in all service repos..."
    echo ""
    
    # Make script executable
    chmod +x "$SCRIPT_DIR/github-setup.sh"
    
    # Run environment setup
    if "$SCRIPT_DIR/github-setup.sh"; then
        log_success "GitHub environments created"
        return 0
    else
        log_warning "Environment creation had some issues (check output above)"
        log_info "You can re-run scripts/github-setup.sh later"
        return 0
    fi
}

################################################################################
# Offer to Deploy Infrastructure
################################################################################

offer_infrastructure_deployment() {
    log_header "🏗️  Infrastructure Deployment"
    
    echo -e "${BLUE}Infrastructure deployment will create:${NC}"
    echo "  • Resource groups (rg-xshopai-gh-dev, rg-xshopai-gh-prod)"
    echo "  • Log Analytics + Application Insights"
    echo "  • Key Vault for secrets"
    echo "  • RabbitMQ Container Instance"
    echo "  • Redis Cache"
    echo "  • Databases (Cosmos DB, MySQL, PostgreSQL, SQL Server)"
    echo "  • App Service Plans + App Services (16 services)"
    echo ""
    log_info "Estimated time: 15-20 minutes"
    log_warning "Estimated cost: ~\$183/month (dev) + ~\$815/month (prod)"
    echo ""
    
    if prompt_confirm "Trigger infrastructure deployment now?"; then
        echo ""
        log_info "Opening GitHub Actions in your browser..."
        sleep 2
        
        # Open infrastructure workflow in browser
        if command -v open &> /dev/null; then
            open "https://github.com/xshopai/infrastructure/actions"
        elif command -v xdg-open &> /dev/null; then
            xdg-open "https://github.com/xshopai/infrastructure/actions"
        elif command -v start &> /dev/null; then
            start "https://github.com/xshopai/infrastructure/actions"
        else
            echo ""
            echo "Go to: https://github.com/xshopai/infrastructure/actions"
        fi
        
        echo ""
        log_info "On the GitHub Actions page:"
        echo "  1. Select 'Deploy Infrastructure' workflow"
        echo "  2. Click 'Run workflow'"
        echo "  3. Select environment: 'development'"
        echo "  4. Click 'Run workflow' to start"
        echo ""
        
        if prompt_confirm "Have you triggered the workflow?"; then
            log_success "Great! Infrastructure deployment is running"
            log_info "Monitor progress at: https://github.com/xshopai/infrastructure/actions"
        fi
    else
        log_info "Skipped infrastructure deployment"
        log_info "You can trigger it later from: https://github.com/xshopai/infrastructure/actions"
    fi
    
    echo ""
}

################################################################################
# Display Next Steps
################################################################################

show_next_steps() {
    log_header "📋 What's Next?"
    
    cat << 'EOF'

┌─────────────────────────────────────────────────────────────────────────┐
│                         Deployment Checklist                            │
└─────────────────────────────────────────────────────────────────────────┘

Phase 1: Infrastructure (15-20 min) ✅ Ready to Deploy
────────────────────────────────────────────────────────
  ☐ Monitor infrastructure workflow
    https://github.com/xshopai/infrastructure/actions
  
  ☐ Verify all resources created in Azure Portal
    Resource Group: rg-xshopai-gh-dev
  
  ☐ Verify Key Vault secrets auto-generated
    Secrets: JWT keys, admin password, database passwords


Phase 2: Service Deployments (30-40 min)
────────────────────────────────────────────────────────
  Deploy services in order (after infrastructure completes):
  
  Wave 1 (Foundation):
    ☐ auth-service: https://github.com/xshopai/auth-service/actions
    ☐ user-service: https://github.com/xshopai/user-service/actions
  
  Wave 2 (Core):
    ☐ product-service
    ☐ inventory-service
  
  Wave 3 (Business):
    ☐ cart-service
    ☐ review-service
    ☐ payment-service
  
  Wave 4 (Orchestration):
    ☐ order-service
    ☐ order-processor-service
  
  Wave 5 (Supporting):
    ☐ notification-service
    ☐ audit-service
    ☐ admin-service
    ☐ chat-service
  
  Wave 6 (Gateway & UI):
    ☐ web-bff
    ☐ customer-ui
    ☐ admin-ui


Phase 3: Verification
────────────────────────────────────────────────────────
  ☐ Run health checks
    ./scripts/verify.sh --env dev
  
  ☐ Check Application Insights
    Azure Portal → appi-xshopai-gh-dev → Application Map
  
  ☐ Test end-to-end flow
    Register user → Browse products → Add to cart → Create order


Phase 4: Production Deployment (Optional)
────────────────────────────────────────────────────────
  ☐ Trigger infrastructure workflow → Select 'production'
  ☐ Deploy services → Requires 2 approvers
  ☐ Configure custom domains (optional)
  ☐ Enable SSL certificates (optional)


Need Help?
────────────────────────────────────────────────────────
  📖 Architecture Guide: ./ARCHITECTURE.md
  🔍 Verify Deployment: ./scripts/verify.sh
  🧹 Clean Up: ./scripts/cleanup.sh

EOF
    
    echo ""
    log_success "Setup Complete! 🎉"
    echo ""
}

################################################################################
# Main Execution Flow
################################################################################

main() {
    clear
    
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║              xshopai Platform - Azure App Service Deployment             ║
║                         One-Click Setup Script                           ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

This script will configure everything needed to deploy the xshopai platform
to Azure App Service using GitHub Actions.

What this does:
  ✅ Authenticates to Azure and GitHub
  ✅ Creates Service Principal for GitHub Actions
  ✅ Configures GitHub organization secrets (automatic if gh CLI available)
  ✅ Creates GitHub environments in all service repos
  ✅ Offers to trigger infrastructure deployment

Note: ACR, databases, and all other resources are created by Bicep templates

Time required: 10-15 minutes (mostly automated)

EOF
    
    if ! prompt_confirm "Ready to begin?"; then
        echo ""
        log_info "Setup cancelled. Run ./scripts/deploy.sh when ready."
        exit 0
    fi
    
    echo ""
    echo ""
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Authenticate to Azure
    auth_azure
    
    # Step 3: Authenticate to GitHub (if CLI available)
    auth_github
    
    # Step 4: Run bootstrap (Service Principal)
    if ! run_bootstrap; then
        log_error "Bootstrap failed. Please check errors above."
        exit 1
    fi
    
    echo ""
    echo ""
    
    # Step 5: Setup GitHub environments
    setup_github_environments
    
    echo ""
    echo ""
    
    # Step 6: Offer to trigger infrastructure deployment
    offer_infrastructure_deployment
    
    # Step 7: Display next steps
    show_next_steps
    
    # Done
    log_header "✅ All Set!"
    log_info "Your environment is configured and ready for deployment"
    echo ""
}

################################################################################
# Run Main
################################################################################

# Check if running from correct directory
if [ ! -f "$SCRIPT_DIR/common.sh" ]; then
    echo "❌ Error: Please run this script from its location in scripts/ directory"
    echo "   cd infrastructure/azure/app-service"
    echo "   ./scripts/deploy.sh"
    exit 1
fi

main "$@"
