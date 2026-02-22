#!/bin/bash
# =============================================================================
# Setup Key Vault RBAC Access
# =============================================================================
# This script helps you configure Azure AD Object ID for Key Vault access
# Run this to grant yourself permission to view secrets in the Key Vault

set -e

echo "=================================================="
echo "Key Vault RBAC Access Setup"
echo "=================================================="
echo ""

# Get current user's Object ID
echo "🔍 Getting your Azure AD Object ID..."
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

if [ -z "$OBJECT_ID" ]; then
  echo "❌ Could not get your Object ID. Make sure you're logged in with 'az login'"
  exit 1
fi

echo "✅ Your Azure AD Object ID: $OBJECT_ID"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
  echo "⚠️  GitHub CLI (gh) is not installed"
  echo "   Install from: https://cli.github.com/"
  echo ""
  echo "📝 Manual setup instructions:"
  echo "   1. Go to: https://github.com/xshopai/infrastructure/settings/secrets/actions"
  echo "   2. Click 'New repository secret'"
  echo "   3. Name: KEYVAULT_ADMIN_OBJECT_ID"
  echo "   4. Value: $OBJECT_ID"
  exit 1
fi

# Set GitHub secret
echo "🔐 Setting GitHub repository secret..."
echo "$OBJECT_ID" | gh secret set KEYVAULT_ADMIN_OBJECT_ID --repo xshopai/infrastructure

if [ $? -eq 0 ]; then
  echo "✅ Secret KEYVAULT_ADMIN_OBJECT_ID set successfully!"
  echo ""
  echo "📋 Next steps:"
  echo "   1. Push changes to trigger deployment"
  echo "   2. Wait for deployment to complete (~10 minutes)"
  echo "   3. You'll now have Key Vault Secrets Officer access"
  echo "   4. Refresh Azure Portal to view secrets"
else
  echo "❌ Failed to set secret. Please set it manually:"
  echo "   1. Go to: https://github.com/xshopai/infrastructure/settings/secrets/actions"
  echo "   2. Click 'New repository secret'"
  echo "   3. Name: KEYVAULT_ADMIN_OBJECT_ID"
  echo "   4. Value: $OBJECT_ID"
fi
