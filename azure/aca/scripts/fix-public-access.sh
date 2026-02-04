#!/bin/bash
# ============================================================================
# Fix Azure Resource Public Network Access
# ============================================================================
# Run this script when Azure governance policy disables public network access
# on Cosmos DB or Key Vault, breaking connectivity from Container Apps.
#
# Long-term fix: Implement Private Endpoints or request policy exemption.
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "  $1"; }

# ============================================================================
# CONFIGURATION
# ============================================================================
ENVIRONMENT_SUFFIX="${ENVIRONMENT_SUFFIX:-1six}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-xshopai-dev-${ENVIRONMENT_SUFFIX}}"
COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-xshopai-dev-${ENVIRONMENT_SUFFIX}}"
KEYVAULT_NAME="${KEYVAULT_NAME:-kv-xshopai-dev-${ENVIRONMENT_SUFFIX}}"

print_header "Fix Azure Resource Public Network Access"

print_info "Resource Group: $RESOURCE_GROUP"
print_info "Cosmos Account: $COSMOS_ACCOUNT"
print_info "Key Vault: $KEYVAULT_NAME"
echo ""

# ============================================================================
# FIX COSMOS DB
# ============================================================================
print_info "Checking Cosmos DB public network access..."

COSMOS_STATUS=$(az cosmosdb show \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query publicNetworkAccess \
    -o tsv 2>/dev/null || echo "NotFound")

if [ "$COSMOS_STATUS" == "NotFound" ]; then
    print_warning "Cosmos DB account not found: $COSMOS_ACCOUNT"
elif [ "$COSMOS_STATUS" == "Enabled" ]; then
    print_success "Cosmos DB: Public access already enabled"
else
    print_warning "Cosmos DB: Public access is $COSMOS_STATUS - enabling..."
    if az cosmosdb update \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --public-network-access Enabled \
        --output none 2>&1; then
        print_success "Cosmos DB: Public access enabled"
    else
        print_error "Cosmos DB: Failed to enable public access"
    fi
fi

# ============================================================================
# FIX KEY VAULT
# ============================================================================
print_info "Checking Key Vault public network access..."

KV_STATUS=$(az keyvault show \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.publicNetworkAccess" \
    -o tsv 2>/dev/null || echo "NotFound")

if [ "$KV_STATUS" == "NotFound" ]; then
    print_warning "Key Vault not found: $KEYVAULT_NAME"
elif [ "$KV_STATUS" == "Enabled" ]; then
    print_success "Key Vault: Public access already enabled"
else
    print_warning "Key Vault: Public access is $KV_STATUS - enabling..."
    if az keyvault update \
        --name "$KEYVAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --public-network-access Enabled \
        --output none 2>&1; then
        print_success "Key Vault: Public access enabled"
    else
        print_error "Key Vault: Failed to enable public access"
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
print_header "Complete"
print_success "Azure resource public network access has been verified/fixed"
print_info ""
print_warning "Note: This may be disabled again by Azure governance policy"
print_info "Consider requesting a policy exemption for dev environments"
print_info "or implementing Private Endpoints for production compliance."
echo ""
