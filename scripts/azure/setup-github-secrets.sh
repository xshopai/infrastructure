#!/bin/bash
# ============================================================================
# GitHub Secrets Setup Script for xshopai
# ============================================================================
# This script configures GitHub organization secrets required for Azure
# Container Apps deployment using OIDC authentication.
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - Azure CLI (az) logged in
#   - Admin access to the GitHub organization
#   - Azure AD App already created (run setup-azure-oidc.sh first)
#
# Usage:
#   ./setup-github-secrets.sh
#
# ============================================================================

set -e

# ============================================================================
# CONFIGURATION - Modify these variables as needed
# ============================================================================
GITHUB_ORG="xshopai"                           # GitHub organization name
APP_DISPLAY_NAME="xshopai-github-actions"      # Azure AD App name (must match setup-azure-oidc.sh)

# ============================================================================
# COLORS FOR OUTPUT
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

echo ""
echo "========================================================"
echo "  GitHub Secrets Setup for xshopai"
echo "========================================================"
echo ""

# Check prerequisites
log_info "Checking prerequisites..."
check_command "gh"
check_command "az"

# Check GitHub CLI authentication
log_info "Verifying GitHub CLI authentication..."
if ! gh auth status &> /dev/null; then
    log_error "GitHub CLI is not authenticated. Please run: gh auth login"
    exit 1
fi
log_success "GitHub CLI authenticated"

# Check Azure CLI authentication
log_info "Verifying Azure CLI authentication..."
if ! az account show &> /dev/null; then
    log_error "Azure CLI is not authenticated. Please run: az login"
    exit 1
fi
log_success "Azure CLI authenticated"

# Get Azure values
log_info "Retrieving Azure configuration..."

# Get Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
if [ -z "$TENANT_ID" ]; then
    log_error "Failed to get Azure Tenant ID"
    exit 1
fi
log_success "Tenant ID: $TENANT_ID"

# Get Subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [ -z "$SUBSCRIPTION_ID" ]; then
    log_error "Failed to get Azure Subscription ID"
    exit 1
fi
log_success "Subscription ID: $SUBSCRIPTION_ID"

# Get Client ID from Azure AD App
log_info "Looking up Azure AD Application: $APP_DISPLAY_NAME"
CLIENT_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)
if [ -z "$CLIENT_ID" ]; then
    log_error "Azure AD Application '$APP_DISPLAY_NAME' not found."
    log_error "Please run setup-azure-oidc.sh first to create the application."
    exit 1
fi
log_success "Client ID: $CLIENT_ID"

echo ""
echo "========================================================"
echo "  Setting GitHub Organization Secrets"
echo "========================================================"
echo ""

# Set AZURE_CLIENT_ID
log_info "Setting AZURE_CLIENT_ID..."
if gh secret set AZURE_CLIENT_ID --org "$GITHUB_ORG" --body "$CLIENT_ID" 2>/dev/null; then
    log_success "AZURE_CLIENT_ID set successfully"
else
    log_warning "Failed to set AZURE_CLIENT_ID at org level. Trying with visibility flag..."
    gh secret set AZURE_CLIENT_ID --org "$GITHUB_ORG" --visibility all --body "$CLIENT_ID"
    log_success "AZURE_CLIENT_ID set successfully"
fi

# Set AZURE_TENANT_ID
log_info "Setting AZURE_TENANT_ID..."
if gh secret set AZURE_TENANT_ID --org "$GITHUB_ORG" --body "$TENANT_ID" 2>/dev/null; then
    log_success "AZURE_TENANT_ID set successfully"
else
    log_warning "Failed to set AZURE_TENANT_ID at org level. Trying with visibility flag..."
    gh secret set AZURE_TENANT_ID --org "$GITHUB_ORG" --visibility all --body "$TENANT_ID"
    log_success "AZURE_TENANT_ID set successfully"
fi

# Set AZURE_SUBSCRIPTION_ID
log_info "Setting AZURE_SUBSCRIPTION_ID..."
if gh secret set AZURE_SUBSCRIPTION_ID --org "$GITHUB_ORG" --body "$SUBSCRIPTION_ID" 2>/dev/null; then
    log_success "AZURE_SUBSCRIPTION_ID set successfully"
else
    log_warning "Failed to set AZURE_SUBSCRIPTION_ID at org level. Trying with visibility flag..."
    gh secret set AZURE_SUBSCRIPTION_ID --org "$GITHUB_ORG" --visibility all --body "$SUBSCRIPTION_ID"
    log_success "AZURE_SUBSCRIPTION_ID set successfully"
fi

echo ""
echo "========================================================"
echo "  Verifying Secrets"
echo "========================================================"
echo ""

log_info "Listing organization secrets..."
gh secret list --org "$GITHUB_ORG"

echo ""
echo "========================================================"
echo "  Setup Complete!"
echo "========================================================"
echo ""
echo "The following secrets have been configured for the '$GITHUB_ORG' organization:"
echo ""
echo "  AZURE_CLIENT_ID ......... $CLIENT_ID"
echo "  AZURE_TENANT_ID ......... $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID ... $SUBSCRIPTION_ID"
echo ""
echo "These secrets are now available to all repositories in the organization."
echo ""
echo "Next steps:"
echo "  1. Verify secrets at: https://github.com/organizations/$GITHUB_ORG/settings/secrets/actions"
echo "  2. Run infrastructure deployment via GitHub Actions"
echo "  3. Run post-deploy-config.sh after infrastructure deployment"
echo ""
