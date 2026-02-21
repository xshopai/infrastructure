#!/usr/bin/env bash
# =============================================================================
# xShopAI Infrastructure Setup - Master Script
# =============================================================================
# Run this ONCE before first deployment to set up all prerequisites.
# Handles GitHub and Azure authentication + secrets setup.
#
# Usage:
#   ./setup-all.sh
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=============================================="
echo "  xShopAI Infrastructure Setup (OIDC)"
echo "=============================================="
echo ""
echo "This script will set up:"
echo "  1. GitHub CLI authentication"
echo "  2. Azure CLI authentication"
echo "  3. Azure AD App with OIDC federation"
echo "  4. GitHub organization secrets (OIDC)"
echo "  5. Infrastructure repo secrets"
echo "  6. GitHub environments in all repos"
echo ""

# =============================================================================
# Step 1: GitHub CLI Authentication
# =============================================================================
echo -e "${BLUE}Step 1/5: GitHub CLI Authentication${NC}"
echo "------------------------------------------------------------------------"

if ! command -v gh &>/dev/null; then
  echo -e "${RED}✗ GitHub CLI not installed${NC}"
  echo "  Install from: https://cli.github.com/"
  exit 1
fi
echo -e "${GREEN}✓ GitHub CLI installed${NC}"

if ! gh auth status &>/dev/null 2>&1; then
  echo -e "${YELLOW}! GitHub CLI not authenticated${NC}"
  "$SCRIPT_DIR/gh-auth.sh"
else
  echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"
fi

# =============================================================================
# Step 2: Azure CLI Authentication
# =============================================================================
echo ""
echo -e "${BLUE}Step 2/5: Azure CLI Authentication${NC}"
echo "------------------------------------------------------------------------"

if ! command -v az &>/dev/null; then
  echo -e "${RED}✗ Azure CLI not installed${NC}"
  echo "  Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi
echo -e "${GREEN}✓ Azure CLI installed${NC}"

if ! az account show &>/dev/null 2>&1; then
  echo -e "${YELLOW}! Azure CLI not authenticated${NC}"
  echo "  Running: az login"
  az login
fi
echo -e "${GREEN}✓ Azure CLI authenticated${NC}"

# Show subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "  Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# =============================================================================
# Step 3: Azure AD App + OIDC Federation
# =============================================================================
echo ""
echo -e "${BLUE}Step 3/5: Azure AD App + OIDC Federation${NC}"
echo "------------------------------------------------------------------------"
"$SCRIPT_DIR/setup-azure-oidc.sh"

# =============================================================================
# Step 4: GitHub Secrets (OIDC + Repo Secrets)
# =============================================================================
echo ""
echo -e "${BLUE}Step 4/5: GitHub Secrets${NC}"
echo "------------------------------------------------------------------------"
"$SCRIPT_DIR/setup-github-secrets.sh"

# =============================================================================
# Step 5: GitHub Environments
# =============================================================================
echo ""
echo -e "${BLUE}Step 5/5: GitHub Environments${NC}"
echo "------------------------------------------------------------------------"
"$SCRIPT_DIR/setup-github-environments.sh"

# =============================================================================
# Done
# =============================================================================
echo ""
echo "=============================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Deploy infrastructure:"
echo "     gh workflow run deploy-app-service-bicep.yml -R xshopai/infrastructure \\"
echo "       -f environment=dev -f suffix=bicep"
echo ""
echo "  2. Deploy a service:"
echo "     gh workflow run ci-app-service.yml -R xshopai/user-service \\"
echo "       -f environment=dev -f suffix=bicep"
