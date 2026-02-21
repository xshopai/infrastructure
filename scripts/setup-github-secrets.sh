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
if ! gh auth status &>/dev/null 2>&1; then
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
# STEP 1: Organization-Level Secrets (OIDC)
# =============================================================================
echo ""
echo -e "${BLUE}Step 1: Organization-Level Secrets (OIDC)${NC}"
echo "------------------------------------------------------------------------"

set_org_secret() {
  local name="$1"
  local value="$2"
  
  if gh secret list --org "$GITHUB_ORG" 2>/dev/null | grep -q "^$name"; then
    echo -e "  ${GREEN}✓ $name (exists)${NC}"
  else
    echo "$value" | gh secret set "$name" --org "$GITHUB_ORG" --visibility all
    echo -e "  ${GREEN}✓ $name (created)${NC}"
  fi
}

set_org_secret "AZURE_CLIENT_ID" "$CLIENT_ID"
set_org_secret "AZURE_TENANT_ID" "$TENANT_ID"
set_org_secret "AZURE_SUBSCRIPTION_ID" "$SUBSCRIPTION_ID"

echo ""
echo -e "  ${GREEN}✓ OIDC secrets never expire - token exchange, no rotation needed!${NC}"

# =============================================================================
# STEP 2: Infrastructure Repo Secrets (Auto-Generated)
# =============================================================================
echo ""
echo -e "${BLUE}Step 2: Infrastructure Repository Secrets${NC}"
echo "------------------------------------------------------------------------"

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
  
  if gh secret list --repo "$INFRA_REPO" 2>/dev/null | grep -q "^$name"; then
    echo -e "  ${GREEN}✓ $name (exists)${NC}"
    return 0
  else
    local value
    value=$($generator)
    echo "$value" | gh secret set "$name" --repo "$INFRA_REPO"
    echo -e "  ${GREEN}✓ $name (created)${NC}"
    return 1
  fi
}

CREATED=0

# Database passwords
ensure_secret "POSTGRES_ADMIN_PASSWORD" gen_password Pg 20 || ((CREATED++)) || true
ensure_secret "MYSQL_ADMIN_PASSWORD" gen_password Mysql 20 || ((CREATED++)) || true
ensure_secret "SQL_ADMIN_PASSWORD" gen_password Sql 20 || ((CREATED++)) || true
ensure_secret "RABBITMQ_PASSWORD" gen_password Rmq 20 || ((CREATED++)) || true

# JWT
ensure_secret "JWT_SECRET" openssl rand -base64 48 || ((CREATED++)) || true

# Service tokens
ensure_secret "ADMIN_SERVICE_TOKEN" gen_token admin-service || ((CREATED++)) || true
ensure_secret "AUTH_SERVICE_TOKEN" gen_token auth-service || ((CREATED++)) || true
ensure_secret "USER_SERVICE_TOKEN" gen_token user-service || ((CREATED++)) || true
ensure_secret "CART_SERVICE_TOKEN" gen_token cart-service || ((CREATED++)) || true
ensure_secret "ORDER_SERVICE_TOKEN" gen_token order-service || ((CREATED++)) || true
ensure_secret "PRODUCT_SERVICE_TOKEN" gen_token product-service || ((CREATED++)) || true
ensure_secret "WEB_BFF_TOKEN" gen_token web-bff || ((CREATED++)) || true

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=============================================="
echo ""

if [ "$CREATED" -gt 0 ]; then
  echo -e "${YELLOW}$CREATED new secrets were created.${NC}"
fi

echo ""
echo "------------------------------------------------------------------------"
echo "Current Setup:"
echo ""
echo -e "${BLUE}Organization Secrets (OIDC):${NC}"
gh secret list --org "$GITHUB_ORG" 2>/dev/null | grep -E "^AZURE" || echo "  (none)"
echo ""
echo -e "${BLUE}Infrastructure Repo Secrets:${NC}"
gh secret list --repo "$INFRA_REPO" 2>/dev/null || echo "  (none)"
echo ""
echo "------------------------------------------------------------------------"
echo "Architecture (OIDC):"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │                    ORGANIZATION LEVEL                       │"
echo "  │  AZURE_CLIENT_ID + TENANT_ID + SUBSCRIPTION_ID              │"
echo "  │                          │                                  │"
echo "  │           GitHub OIDC Token Exchange (no secrets!)          │"
echo "  │                          │                                  │"
echo "  │                          ▼                                  │"
echo "  │               All repos can deploy to Azure                 │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │               INFRASTRUCTURE REPO ONLY                      │"
echo "  │  DB Passwords, JWT, Service Tokens                          │"
echo "  │         │                                                   │"
echo "  │         ▼                                                   │"
echo "  │  Bicep Workflow ───────────────► Azure Key Vault            │"
echo "  └─────────────────────────────────────────────────────────────┘"
