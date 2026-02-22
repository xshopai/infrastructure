#!/usr/bin/env bash
# ============================================================================
# GitHub Secrets Setup for xshopai (OIDC - Fully Automated)
# ============================================================================
# Sets up GitHub secrets for OIDC authentication.
# Requires: setup-azure-oidc.sh must be run first to create the Azure AD App.
#
# Creates:
#   - Org secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
#   - Infra repo secrets: DB passwords, JWT, service tokens (auto-generated)
#   - Infra repo secret: KEYVAULT_ADMIN_OBJECT_ID (for Key Vault RBAC access)
#
# Prerequisites:
#   - gh CLI authenticated with org admin access
#   - az CLI authenticated
#   - Azure AD App exists (run setup-azure-oidc.sh first)
#   - openssl installed
#
# Usage:
#   ./setup-github-secrets.sh
# ============================================================================

set -euo pipefail

GITHUB_ORG="xshopai"
INFRA_REPO="xshopai/infrastructure"
APP_DISPLAY_NAME="xshopai-github-actions"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=============================================="
echo "  GitHub Secrets Setup (OIDC)"
echo "=============================================="
echo ""

# =============================================================================
# Prerequisites Check
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}Prerequisites Check${NC}"
echo "------------------------------------------------------------------------"

# Check gh CLI
if ! command -v gh &>/dev/null; then
  echo -e "${RED}✗ gh CLI not installed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ gh CLI installed${NC}"

# Check gh auth - use gh-auth.sh if not authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo -e "${YELLOW}! gh CLI not authenticated${NC}"
  if [ -f "$SCRIPT_DIR/gh-auth.sh" ]; then
    "$SCRIPT_DIR/gh-auth.sh"
  else
    echo "  Run: gh auth login"
    exit 1
  fi
fi
echo -e "${GREEN}✓ gh CLI authenticated${NC}"

# Check az CLI
if ! command -v az &>/dev/null; then
  echo -e "${RED}✗ az CLI not installed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ az CLI installed${NC}"

# Check az auth
if ! az account show &>/dev/null 2>&1; then
  echo -e "${YELLOW}! az CLI not authenticated${NC}"
  az login
fi
echo -e "${GREEN}✓ az CLI authenticated${NC}"

# Check openssl
if ! command -v openssl &>/dev/null; then
  echo -e "${RED}✗ openssl not installed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ openssl installed${NC}"

# Get Azure values
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Get Client ID from Azure AD App (must have run setup-azure-oidc.sh first)
CLIENT_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -z "$CLIENT_ID" ]; then
  echo -e "${RED}✗ Azure AD App '$APP_DISPLAY_NAME' not found${NC}"
  echo "  Run setup-azure-oidc.sh first to create the Azure AD App"
  exit 1
fi
echo -e "${GREEN}✓ Azure AD App found: $CLIENT_ID${NC}"

# =============================================================================
# STEP 1: Clean Up Legacy Secrets (from old SP approach)
# =============================================================================
echo ""
echo -e "${BLUE}Step 1: Clean Up Legacy Secrets${NC}"
echo "------------------------------------------------------------------------"

# Remove old SP-based secrets that are no longer needed with OIDC
for legacy_secret in AZURE_CLIENT_SECRET AZURE_CREDENTIALS; do
  # Check if secret exists by checking exit code
  if gh secret list --org "$GITHUB_ORG" 2>/dev/null | grep -q "^$legacy_secret"; then
    gh secret delete "$legacy_secret" --org "$GITHUB_ORG" >/dev/null 2>&1 || true
    echo -e "  ${YELLOW}✓ $legacy_secret (deleted - not needed for OIDC)${NC}"
  fi
done

# =============================================================================
# STEP 2: Organization-Level Secrets (OIDC) - Always Overwrite
# =============================================================================
echo ""
echo -e "${BLUE}Step 2: Organization-Level Secrets (OIDC)${NC}"
echo "------------------------------------------------------------------------"

set_org_secret() {
  local name="$1"
  local value="$2"
  
  # Always overwrite to ensure correct values
  echo "$value" | gh secret set "$name" --org "$GITHUB_ORG" --visibility all
  echo -e "  ${GREEN}✓ $name (set)${NC}"
}

set_org_secret "AZURE_CLIENT_ID" "$CLIENT_ID"
set_org_secret "AZURE_TENANT_ID" "$TENANT_ID"
set_org_secret "AZURE_SUBSCRIPTION_ID" "$SUBSCRIPTION_ID"

echo ""
echo -e "  ${GREEN}✓ OIDC secrets set - token exchange, no rotation needed!${NC}"

# =============================================================================
# STEP 3: Organization-Level Variables (Deployment Configuration)
# =============================================================================
echo ""
echo -e "${BLUE}Step 3: Organization-Level Variables (Deployment)${NC}"
echo "------------------------------------------------------------------------"

set_org_variable() {
  local name="$1"
  local value="$2"
  
  # Always overwrite to ensure correct values
  gh variable set "$name" --org "$GITHUB_ORG" --visibility all --body "$value"
  echo -e "  ${GREEN}✓ $name = $value${NC}"
}

set_org_variable "DEPLOY_SUFFIX_DEV" "development"
set_org_variable "DEPLOY_SUFFIX_PROD" "production"

echo ""
echo -e "  ${GREEN}✓ Deployment suffix variables set for all repositories${NC}"

# =============================================================================
# STEP 4: Infrastructure Repo Secrets (Auto-Generated)
# =============================================================================
echo ""
echo -e "${BLUE}Step 4: Infrastructure Repository Secrets${NC}"
echo "------------------------------------------------------------------------"
echo -e "  ${YELLOW}Note: Repo secrets are only created if missing (to preserve deployed app configs)${NC}"
echo ""

# Helper to generate secure password
gen_password() {
  local prefix="${1:-Xshop}" len="${2:-20}"
  echo "${prefix}$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$len")!"
}

# Helper to generate token
gen_token() {
  local name="$1"
  echo "svc-${name}-$(openssl rand -hex 16)"
}

# Check if secret exists, generate if missing
ensure_secret() {
  local name="$1"
  shift
  local generator="$@"
  
  # Check if secret exists by verifying gh secret list output
  if gh secret list --repo "$INFRA_REPO" 2>/dev/null | grep -q "^$name"; then
    echo -e "  ${GREEN}✓ $name (exists)${NC}"
    return 0
  else
    # Temporarily disable exit on error for proper error handling
    set +e
    local value
    value=$($generator)
    local gen_exit=$?
    
    if [ $gen_exit -ne 0 ]; then
      set -e
      echo -e "  ${RED}✗ $name (failed to generate)${NC}"
      return 2
    fi
    
    echo "$value" | gh secret set "$name" --repo "$INFRA_REPO" >/dev/null 2>&1
    local set_exit=$?
    set -e
    
    if [ $set_exit -eq 0 ]; then
      echo -e "  ${GREEN}✓ $name (created)${NC}"
      return 1
    else
      echo -e "  ${RED}✗ $name (failed to set)${NC}"
      return 2
    fi
  fi
}

CREATED=0
FAILED=0

# Helper function to track secret creation - prevents set -e from exiting
track_secret() {
  set +e
  ensure_secret "$@"
  local exit_code=$?
  set -e
  
  if [ $exit_code -eq 1 ]; then
    CREATED=$((CREATED + 1))
  elif [ $exit_code -eq 2 ]; then
    FAILED=$((FAILED + 1))
  fi
  return 0
}

# Database passwords
track_secret "POSTGRES_ADMIN_PASSWORD" gen_password Pg 20
track_secret "MYSQL_ADMIN_PASSWORD" gen_password Mysql 20
track_secret "SQL_ADMIN_PASSWORD" gen_password Sql 20
track_secret "RABBITMQ_PASSWORD" gen_password Rmq 20

# JWT
track_secret "JWT_SECRET" openssl rand -base64 48

# Service tokens
track_secret "ADMIN_SERVICE_TOKEN" gen_token admin-service
track_secret "AUTH_SERVICE_TOKEN" gen_token auth-service
track_secret "USER_SERVICE_TOKEN" gen_token user-service
track_secret "CART_SERVICE_TOKEN" gen_token cart-service
track_secret "ORDER_SERVICE_TOKEN" gen_token order-service
track_secret "PRODUCT_SERVICE_TOKEN" gen_token product-service
track_secret "WEB_BFF_TOKEN" gen_token web-bff

# Key Vault RBAC - get current user's Object ID for Key Vault access
echo -e "\n${BLUE}Setting Key Vault Admin Access${NC}"
echo "------------------------------------------------------------------------"
KEYVAULT_ADMIN_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [ -z "$KEYVAULT_ADMIN_OBJECT_ID" ]; then
  echo -e "  ${YELLOW}⚠ Could not get Object ID (not logged in as user?)${NC}"
  echo -e "  ${YELLOW}  Key Vault RBAC access will not be configured${NC}"
  echo -e "  ${YELLOW}  Run: az ad signed-in-user show --query id -o tsv${NC}"
  echo -e "  ${YELLOW}  Then manually set: gh secret set KEYVAULT_ADMIN_OBJECT_ID --repo $INFRA_REPO${NC}"
else
  echo -e "  ${BLUE}ℹ Current user Object ID: $KEYVAULT_ADMIN_OBJECT_ID${NC}"
  track_secret "KEYVAULT_ADMIN_OBJECT_ID" echo "$KEYVAULT_ADMIN_OBJECT_ID"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
if [ "$FAILED" -gt 0 ]; then
  echo -e "${RED}Setup Completed with Errors${NC}"
else
  echo -e "${GREEN}Setup Complete!${NC}"
fi
echo "=============================================="
echo ""

if [ "$CREATED" -gt 0 ]; then
  echo -e "${YELLOW}$CREATED new secrets were created.${NC}"
fi

if [ "$FAILED" -gt 0 ]; then
  echo -e "${RED}$FAILED secrets failed to create.${NC}"
  echo -e "${YELLOW}Review the output above for details.${NC}"
fi

echo ""
echo "------------------------------------------------------------------------"
echo "Current Setup:"
echo ""
echo -e "${BLUE}Organization Secrets (OIDC):${NC}"
gh secret list --org "$GITHUB_ORG" 2>/dev/null | grep -E "^AZURE" || echo "  (none)"
echo ""
echo -e "${BLUE}Organization Variables (Deployment):${NC}"
gh variable list --org "$GITHUB_ORG" 2>/dev/null | grep -E "^DEPLOY_SUFFIX" || echo "  (none)"
echo ""
echo -e "${BLUE}Infrastructure Repo Secrets:${NC}"
gh secret list --repo "$INFRA_REPO" 2>/dev/null || echo "  (none)"
echo ""
echo "------------------------------------------------------------------------"
echo "Architecture (OIDC):"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │                    ORGANIZATION LEVEL                       │"
echo "  │  Secrets: AZURE_CLIENT_ID + TENANT_ID + SUBSCRIPTION_ID     │"
echo "  │  Variables: DEPLOY_SUFFIX_DEV, DEPLOY_SUFFIX_PROD          │"
echo "  │                          │                                  │"
echo "  │           GitHub OIDC Token Exchange (no secrets!)          │"
echo "  │                          │                                  │"
echo "  │                          ▼                                  │"
echo "  │               All repos can deploy to Azure                 │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │               INFRASTRUCTURE REPO ONLY                      │"
echo "  │  DB Passwords, JWT, Service Tokens, Key Vault RBAC         │"
echo "  │         │                                                   │"
echo "  │         ▼                                                   │"
echo "  │  Bicep Workflow ───────────────► Azure Key Vault            │"
echo "  └─────────────────────────────────────────────────────────────┘"
