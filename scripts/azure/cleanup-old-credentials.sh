#!/bin/bash
# ============================================================================
# Cleanup Old Federated Credentials
# ============================================================================
# This script removes old per-repo federated credentials to make room for
# the new job_workflow_ref approach.
#
# Usage:
#   chmod +x cleanup-old-credentials.sh
#   ./cleanup-old-credentials.sh
# ============================================================================

set -e

APP_DISPLAY_NAME="xshopai-github-actions"

echo "============================================"
echo "Cleanup Old Federated Credentials"
echo "============================================"
echo ""

# Check if Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    echo "❌ Error: Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Get App Object ID
APP_OBJECT_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [ -z "$APP_OBJECT_ID" ] || [ "$APP_OBJECT_ID" == "None" ]; then
    echo "❌ Error: Azure AD Application '$APP_DISPLAY_NAME' not found."
    exit 1
fi

echo "📋 App Object ID: $APP_OBJECT_ID"
echo ""

# List all current credentials
echo "📋 Current federated credentials:"
echo "-------------------------------------------"
az ad app federated-credential list --id $APP_OBJECT_ID --query "[].{Name:name, Subject:subject}" -o table
echo ""

# Get all credential names
CREDENTIALS=$(az ad app federated-credential list --id $APP_OBJECT_ID --query "[].name" -o tsv)

# Credentials to KEEP (the new approach)
KEEP_CREDENTIALS=(
    "reusable-deploy-container-app"
    "infrastructure-main"
    "infrastructure-env-dev"
    "infrastructure-env-staging"
    "infrastructure-env-prod"
)

echo "🗑️  Credentials to DELETE (old per-repo style):"
echo "-------------------------------------------"

TO_DELETE=()
for cred in $CREDENTIALS; do
    KEEP=false
    for keep_cred in "${KEEP_CREDENTIALS[@]}"; do
        if [ "$cred" == "$keep_cred" ]; then
            KEEP=true
            break
        fi
    done
    
    if [ "$KEEP" == "false" ]; then
        echo "   - $cred"
        TO_DELETE+=("$cred")
    fi
done

if [ ${#TO_DELETE[@]} -eq 0 ]; then
    echo "   (none - all credentials are already using the new approach)"
    echo ""
    echo "✅ No cleanup needed!"
    exit 0
fi

echo ""
echo "📋 Credentials to KEEP:"
echo "-------------------------------------------"
for keep_cred in "${KEEP_CREDENTIALS[@]}"; do
    for cred in $CREDENTIALS; do
        if [ "$cred" == "$keep_cred" ]; then
            echo "   ✅ $cred"
        fi
    done
done

echo ""
echo "⚠️  This will delete ${#TO_DELETE[@]} credential(s)."
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "🗑️  Deleting old credentials..."

for cred in "${TO_DELETE[@]}"; do
    echo "   Deleting: $cred"
    az ad app federated-credential delete --id $APP_OBJECT_ID --federated-credential-id "$cred" 2>/dev/null || echo "   ⚠️  Failed to delete $cred (may not exist)"
done

echo ""
echo "============================================"
echo "✅ Cleanup Complete!"
echo "============================================"
echo ""
echo "📋 Remaining credentials:"
az ad app federated-credential list --id $APP_OBJECT_ID --query "[].{Name:name, Subject:subject}" -o table
echo ""
echo "🚀 Next step: Run setup-azure-oidc.sh to create the new credentials"
echo ""
