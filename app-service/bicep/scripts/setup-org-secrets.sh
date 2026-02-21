#!/usr/bin/env bash
# =============================================================================
# Setup Secrets for xShopAI (Fully Automated)
# =============================================================================
# Fully automated setup - creates everything needed for first-time deployment:
#   - Creates Azure service principal (if needed)
#   - Sets AZURE_CREDENTIALS at org level
#   - Sets infra repo secrets (DB passwords, JWT, service tokens)
#
# Prerequisites:
#   - gh CLI authenticated with org admin access
#   - az CLI authenticated (az login)
#   - openssl installed
#
# Usage:
#   ./setup-org-secrets.sh
# =============================================================================

set -euo pipefail

ORG="xshopai"
INFRA_REPO="xshopai/infrastructure"
SP_NAME="sp-xshopai-github"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=============================================="
echo "  xShopAI Secrets Setup (Fully Automated)"
echo "=============================================="
echo ""

# =============================================================================
# Prerequisites Check
# =============================================================================
echo -e "${BLUE}Prerequisites Check${NC}"
echo "------------------------------------------------------------------------"

# Check gh CLI
if ! command -v gh &>/dev/null; then
  echo -e "${RED}✗ gh CLI not installed${NC}"
  echo "  Install: https://cli.github.com/"
  exit 1
fi
echo -e "${GREEN}✓ gh CLI installed${NC}"

# Check gh auth
if ! gh auth status &>/dev/null; then
  echo -e "${RED}✗ gh CLI not authenticated${NC}"
  echo "  Run: gh auth login"
  exit 1
fi
echo -e "${GREEN}✓ gh CLI authenticated${NC}"

# Check org access
if ! gh api "orgs/$ORG" &>/dev/null; then
  echo -e "${RED}✗ Cannot access org '$ORG'${NC}"
  echo "  Ensure you have admin access to the organization"
  exit 1
fi
echo -e "${GREEN}✓ org '$ORG' accessible${NC}"

# Check az CLI
if ! command -v az &>/dev/null; then
  echo -e "${RED}✗ az CLI not installed${NC}"
  echo "  Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi
echo -e "${GREEN}✓ az CLI installed${NC}"

# Check az auth
if ! az account show &>/dev/null; then
  echo -e "${RED}✗ az CLI not authenticated${NC}"
  echo "  Run: az login"
  exit 1
fi
echo -e "${GREEN}✓ az CLI authenticated${NC}"

# Check openssl
if ! command -v openssl &>/dev/null; then
  echo -e "${RED}✗ openssl not installed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ openssl installed${NC}"

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo ""
echo -e "${BLUE}Azure Subscription:${NC} $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# =============================================================================
# STEP 1: Organization-Level Secret (AZURE_CREDENTIALS)
# =============================================================================
echo ""
echo -e "${BLUE}Step 1: Organization-Level Secret (AZURE_CREDENTIALS)${NC}"
echo "------------------------------------------------------------------------"

if gh secret list --org "$ORG" 2>/dev/null | grep -q "AZURE_CREDENTIALS"; then
  echo -e "${GREEN}✓ AZURE_CREDENTIALS already exists at org level${NC}"
else
  echo "Creating Azure service principal '$SP_NAME'..."
  
  # Check if SP already exists
  EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")
  
  if [ -n "$EXISTING_SP" ]; then
    echo "  Service principal exists (appId: $EXISTING_SP)"
    echo "  Resetting credentials..."
    
    # Reset credentials and get JSON output
    AZURE_CREDS=$(az ad sp credential reset \
      --id "$EXISTING_SP" \
      --query "{clientId:appId, clientSecret:password, subscriptionId:'$SUBSCRIPTION_ID', tenantId:tenant}" \
      -o json 2>/dev/null)
    
    # Format as expected JSON
    CLIENT_ID=$(echo "$AZURE_CREDS" | jq -r '.clientId')
    CLIENT_SECRET=$(echo "$AZURE_CREDS" | jq -r '.clientSecret')
    TENANT_ID=$(az account show --query tenantId -o tsv)
    
    AZURE_CREDS_JSON=$(cat <<EOF
{"clientId":"$CLIENT_ID","clientSecret":"$CLIENT_SECRET","subscriptionId":"$SUBSCRIPTION_ID","tenantId":"$TENANT_ID"}
EOF
)
  else
    echo "  Creating new service principal..."
    
    # Create new SP with Contributor role
    AZURE_CREDS_JSON=$(az ad sp create-for-rbac \
      --name "$SP_NAME" \
      --role Contributor \
      --scopes "/subscriptions/$SUBSCRIPTION_ID" \
      --json-auth 2>/dev/null)
    
    if [ -z "$AZURE_CREDS_JSON" ]; then
      echo -e "${RED}✗ Failed to create service principal${NC}"
      echo "  Ensure you have sufficient Azure AD permissions"
      exit 1
    fi
  fi
  
  # Set the secret at org level
  echo "$AZURE_CREDS_JSON" | gh secret set AZURE_CREDENTIALS --org "$ORG" --visibility all
  echo -e "${GREEN}✓ AZURE_CREDENTIALS set at org level${NC}"
  
  # Extract and display client ID for reference
  CLIENT_ID=$(echo "$AZURE_CREDS_JSON" | jq -r '.clientId')
  echo "  Service Principal App ID: $CLIENT_ID"
fi

# =============================================================================
# STEP 2: Infrastructure Repo Secrets
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
echo -e "${BLUE}Organization Secrets:${NC}"
gh secret list --org "$ORG" 2>/dev/null | grep -E "^AZURE" || echo "  (none)"
echo ""
echo -e "${BLUE}Infrastructure Repo Secrets:${NC}"
gh secret list --repo "$INFRA_REPO" 2>/dev/null || echo "  (none)"
echo ""
echo "------------------------------------------------------------------------"
echo "Architecture:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │                    ORGANIZATION LEVEL                       │"
echo "  │  AZURE_CREDENTIALS ─────────────────────────► All Repos     │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │               INFRASTRUCTURE REPO ONLY                      │"
echo "  │  DB Passwords, JWT, Service Tokens                          │"
echo "  │         │                                                   │"
echo "  │         ▼                                                   │"
echo "  │  Bicep Workflow ───────────────► Azure Key Vault            │"
echo "  │                                        │                    │"
echo "  │                                        ▼                    │"
echo "  │                                  App Services               │"
echo "  │                                  (runtime config)           │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "Next steps:"
echo "  1. Deploy infrastructure:"
echo "     gh workflow run deploy-app-service-bicep.yml -R $INFRA_REPO \\"
echo "       -f environment=dev -f suffix=bicep"
echo ""
echo "  2. Deploy a service:"
echo "     gh workflow run ci-app-service.yml -R xshopai/user-service \\"
echo "       -f environment=dev -f suffix=bicep"
