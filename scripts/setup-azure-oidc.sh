#!/bin/bash
# ============================================================================
# Azure OIDC Setup Script for xshopai Platform
# ============================================================================
# This script sets up Azure AD Application with federated credentials for
# GitHub Actions OIDC authentication across all xshopai repositories.
#
# Key Feature: Uses ENVIRONMENT-ONLY GitHub OIDC (minimal credentials!)
# - All services deploying to same environment share ONE credential
# - Total credentials: 2 (development + production) - within 20 limit!
# - No dependency on repo names or workflow filenames
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - GitHub CLI installed and authenticated (gh auth login)
#   - Sufficient permissions to create Azure AD applications
#   - GitHub org admin permissions (to configure OIDC settings)
#
# Usage:
#   chmod +x setup-azure-oidc.sh
#   ./setup-azure-oidc.sh
# ============================================================================

set -e  # Exit on error

# ============================================================================
# CONFIGURATION
# ============================================================================
LOCATION="swedencentral"
GITHUB_ORG="xshopai"
APP_DISPLAY_NAME="xshopai-github-actions"

echo "============================================"
echo "Azure OIDC Setup for xshopai Platform"
echo "============================================"
echo ""

# Check if Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    echo "❌ Error: Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo "📋 Current Azure Context:"
echo "   Subscription: $SUBSCRIPTION_NAME"
echo "   Subscription ID: $SUBSCRIPTION_ID"
echo "   Tenant ID: $TENANT_ID"
echo "   Location: $LOCATION"
echo ""

# ============================================================================
# Step 1: Create or Get Azure AD Application
# ============================================================================

echo ""
echo "🔧 Step 1: Setting up Azure AD Application..."

# Check if app already exists
EXISTING_APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "None" ]; then
    echo "   ✅ Azure AD Application already exists"
    APP_ID=$EXISTING_APP_ID
    APP_OBJECT_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].id" -o tsv)
else
    echo "   Creating new Azure AD Application..."
    APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
    APP_OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)
    echo "   ✅ Created Azure AD Application"
fi

echo "   App ID (Client ID): $APP_ID"
echo "   App Object ID: $APP_OBJECT_ID"

# ============================================================================
# Step 2: Create Service Principal
# ============================================================================

echo ""
echo "🔧 Step 2: Setting up Service Principal..."

SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [ -n "$SP_OBJECT_ID" ] && [ "$SP_OBJECT_ID" != "None" ]; then
    echo "   ✅ Service Principal already exists"
else
    az ad sp create --id $APP_ID > /dev/null
    SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)
    echo "   ✅ Created Service Principal"
fi

echo "   SP Object ID: $SP_OBJECT_ID"

# ============================================================================
# Step 3: Assign Roles to Service Principal (using REST API for reliability)
# ============================================================================

echo ""
echo "🔧 Step 3: Assigning roles to Service Principal..."

# Function to assign role using REST API (more reliable than az role assignment create)
assign_role() {
    local role_name="$1"
    local role_id="$2"
    local assignment_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    
    echo "   Assigning $role_name role..."
    
    # Check if already assigned (with timeout to prevent hanging)
    set +e  # Temporarily disable exit on error
    EXISTING=$(timeout 30s az role assignment list \
        --assignee "$SP_OBJECT_ID" \
        --role "$role_name" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")
    local check_exit=$?
    set -e  # Re-enable exit on error
    
    if [ $check_exit -eq 124 ]; then
        echo "   ⚠️  Timeout checking existing $role_name assignment - will attempt to assign"
    elif [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
        echo "   ✅ $role_name role (already assigned)"
        return 0
    fi
    
    # Use REST API to create role assignment (with timeout)
    set +e
    timeout 60s az rest --method PUT \
        --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/roleAssignments/$assignment_id?api-version=2022-04-01" \
        --body "{
            \"properties\": {
                \"roleDefinitionId\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/roleDefinitions/$role_id\",
                \"principalId\": \"$SP_OBJECT_ID\",
                \"principalType\": \"ServicePrincipal\"
            }
        }" --output none 2>&1
    local assign_exit=$?
    set -e
    
    if [ $assign_exit -eq 0 ]; then
        echo "   ✅ $role_name role assigned"
    elif [ $assign_exit -eq 124 ]; then
        echo "   ⚠️  Timeout assigning $role_name role (may still be in progress)"
    else
        # Role might already exist even if check failed
        echo "   ⚠️  Could not confirm $role_name assignment (may already exist)"
    fi
}

# Role Definition IDs (these are Azure built-in role IDs)
# Contributor: b24988ac-6180-42a0-ab88-20f7382dd24c
# User Access Administrator: 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9
# AcrPush: 8311e382-0749-4cb8-b61a-304f252e45ec
# Key Vault Administrator: 00482a5a-887f-4fb3-b363-3b7fe8e74483

assign_role "Contributor" "b24988ac-6180-42a0-ab88-20f7382dd24c"
assign_role "User Access Administrator" "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"
assign_role "AcrPush" "8311e382-0749-4cb8-b61a-304f252e45ec"
assign_role "Key Vault Administrator" "00482a5a-887f-4fb3-b363-3b7fe8e74483"

# ============================================================================
# Step 4: Configure GitHub OIDC Subject Claims - ENVIRONMENT ONLY
# ============================================================================
#
# IMPORTANT: We use ENVIRONMENT-ONLY GitHub OIDC subject claims!
#
# Environment-only subject claims look like:
#   environment:dev
#   environment:prod
#
# ✅ BENEFITS of environment-only approach:
#   - Minimal credentials: Only 2 total (dev + prod)
#   - Well within Azure AD's 20 credential limit per app registration
#   - No dependency on repo names (can rename repos freely)
#   - No dependency on workflow filenames (can rename workflows freely)
#   - All services deploying to same environment share one credential
#   - Simplest possible configuration
#
# ❌ DO NOT use other approaches because:
#   - "job_workflow_ref": Creates workflow filename dependency
#   - "repo": Creates too many credentials (3 per service × 16 = 48 > 20 limit)
#   - "context": Creates too many credentials
# ============================================================================

echo ""
echo "🔧 Step 4: Configuring GitHub OIDC settings..."

# Unset GH_TOKEN if present (can interfere with gh CLI authentication)
if [ -n "${GH_TOKEN:-}" ]; then
    echo "   ⚠️  Unsetting GH_TOKEN environment variable (can interfere with gh CLI)"
    unset GH_TOKEN
fi

# Check if GitHub CLI is authenticated
set +e  # Temporarily disable exit on error
gh auth status 2>&1 | head -5
GH_AUTH_EXIT=$?
set -e  # Re-enable exit on error

if [ $GH_AUTH_EXIT -ne 0 ]; then
    echo "   ❌ Error: GitHub CLI not authenticated properly."
    echo "   Please run: gh auth login --scopes admin:org"
    exit 1
fi

echo "   Configuring environment-only GitHub OIDC..."
echo "   This ensures NO dependency on repo names or workflow filenames!"
echo "   Only 2 credentials needed total (development + production)!"

# NOTE: Organization-level OIDC API doesn't support custom configurations
#       So we configure each repo individually instead

echo ""
echo "   Configuring infrastructure repo to use environment-only OIDC..."
gh api -X PUT "repos/${GITHUB_ORG}/infrastructure/actions/oidc/customization/sub" \
    --input - <<EOF > /dev/null 2>&1
{
    "use_default": false,
    "include_claim_keys": ["environment"]
}
EOF
echo "   ✅ Infrastructure repo configured"

echo ""
echo "   Configuring service repos to use environment-only OIDC..."

# List of all service repos
SERVICE_REPOS=(
    "admin-service"
    "admin-ui"
    "audit-service"
    "auth-service"
    "cart-service"
    "chat-service"
    "customer-ui"
    "inventory-service"
    "notification-service"
    "order-processor-service"
    "order-service"
    "payment-service"
    "product-service"
    "review-service"
    "user-service"
    "web-bff"
)

for repo in "${SERVICE_REPOS[@]}"; do
    gh api -X PUT "repos/${GITHUB_ORG}/${repo}/actions/oidc/customization/sub" \
        --input - <<EOF > /dev/null 2>&1
    {
        "use_default": false,
        "include_claim_keys": ["environment"]
    }
EOF
    if [ $? -eq 0 ]; then
        echo "   ✅ ${repo}"
    else
        echo "   ⚠️  ${repo} (may not exist yet)"
    fi
done

echo ""
echo "   📝 All repos now use environment-only OIDC"
echo "   📝 Subject claims will be: environment:dev or environment:prod"

# Verify the configuration
echo ""
echo "   Verifying configuration..."
INFRA_CONFIG=$(gh api "repos/${GITHUB_ORG}/infrastructure/actions/oidc/customization/sub" 2>/dev/null || echo '{}')
echo "   Infrastructure config: $INFRA_CONFIG"

# ============================================================================
# Step 5: Clean Up Old Federated Credentials
# ============================================================================

echo ""
echo "🔧 Step 5: Cleaning up old federated credentials..."

# Get all existing credentials with their IDs (UUIDs)
EXISTING_CREDS=$(az ad app federated-credential list --id $APP_OBJECT_ID --query "[].{name:name,id:id}" -o json 2>/dev/null || echo "[]")
CRED_COUNT=$(echo "$EXISTING_CREDS" | jq '. | length')

if [ "$CRED_COUNT" -gt 0 ]; then
    echo "   Found $CRED_COUNT existing credential(s)"
    echo ""
    echo "   Current credentials:"
    az ad app federated-credential list --id $APP_OBJECT_ID --query "[].{Name:name, Subject:subject}" -o table
    echo ""
    echo "   🗑️  Deleting ALL existing credentials to start fresh..."
    
    # Delete each credential using its UUID (not name!)
    echo "$EXISTING_CREDS" | jq -r '.[] | "\(.id)\t\(.name)"' | while IFS=$'\t' read -r cred_id cred_name; do
        echo "      Deleting: $cred_name (ID: $cred_id)"
        az ad app federated-credential delete --id $APP_OBJECT_ID --federated-credential-id "$cred_id" 2>/dev/null || echo "      ⚠️  Failed to delete (may not exist)"
    done
    
    echo "   ✅ Cleanup complete!"
else
    echo "   No existing credentials found"
fi

# ============================================================================
# Step 6: Create Federated Credentials Using Environment-Only Subject Format
# ============================================================================
# 
# IMPORTANT: We create only 2 federated credentials (environment-based)!
# 
# Environment-only subject patterns:
#   - Development: environment:dev
#   - Production: environment:prod
#
# ALL services deploying to dev share the same credential
# ALL services deploying to prod share the same credential
#
# ✅ Benefits:
#   - Minimal credentials: Only 2 total!
#   - Well within Azure AD's 20 credential limit per app registration
#   - No dependency on repo names (can rename repos freely)
#   - No dependency on workflow filenames (can rename workflows freely)
#   - Simplest possible configuration
#   - Scalable to any number of services
#   - Matches Azure resource naming conventions (rg-xshopai-dev)
# ============================================================================

echo ""
echo "🔧 Step 6: Creating NEW federated credentials..."

# Wait a moment for Azure AD to propagate the deletions
echo "   ⏳ Waiting 5 seconds for Azure AD to propagate deletions..."
sleep 5

create_federated_credential() {
    local name=$1
    local subject=$2
    local description=$3
    
    az ad app federated-credential create --id $APP_OBJECT_ID --parameters "{
        \"name\": \"$name\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"$subject\",
        \"description\": \"$description\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
    }" > /dev/null
    echo "   ✅ Created credential: $name"
}

echo ""
echo "   🌍 Creating environment-based credentials (2 total)..."

# Development environment - shared by ALL services
create_federated_credential \
    "xshopai-dev" \
    "environment:dev" \
    "All xshopai services deploying to dev environment"

# Production environment - shared by ALL services
create_federated_credential \
    "xshopai-prod" \
    "environment:prod" \
    "All xshopai services deploying to prod environment"

echo ""
echo "   ✅ Federated credentials setup complete!"
echo "   Total credentials: 2 (well within the 20 limit)"

# ============================================================================
# Step 7: Display Summary and GitHub Secrets
# ============================================================================

echo ""
echo "============================================"
echo "✅ Azure OIDC Setup Complete!"
echo "============================================"
echo ""
echo "📋 Summary:"
echo "   Azure AD Application: $APP_DISPLAY_NAME"
echo "   Client ID: $APP_ID"
echo "   Tenant ID: $TENANT_ID"
echo "   Subscription ID: $SUBSCRIPTION_ID"
echo ""
echo "============================================"
echo "📋 Final Federated Credentials"
echo "============================================"
echo ""
az ad app federated-credential list --id $APP_OBJECT_ID --query "[].{Name:name, Subject:subject}" -o table
echo ""
echo "============================================"
echo "🎯 How It Works"
echo "============================================"
echo ""
echo "We use ENVIRONMENT-ONLY GitHub OIDC (minimal credentials)!"
echo ""
echo "1. Each repo uses environment-only GitHub OIDC subject claims:"
echo "   environment:dev"
echo "   environment:prod"
echo ""
echo "2. Benefits:"
echo "   ✅ Only 2 credentials total (not 50!)"
echo "   ✅ Well within Azure AD's 20 credential limit"
echo "   ✅ No dependency on repo names"
echo "   ✅ No dependency on workflow filenames"
echo "   ✅ All services deploying to same environment share one credential"
echo "   ✅ Can rename workflows and repos freely"
echo ""
echo "3. Authentication flow:"
echo "   - Service workflow runs in 'dev' environment"
echo "   - GitHub generates token with subject: environment:dev"
echo "   - Azure AD matches this to 'xshopai-dev' credential"
echo "   - All services deploying to dev use same credential"
echo ""
echo "============================================"
echo "🔐 GitHub Organization Secrets to Configure"
echo "============================================"
echo ""
echo "Go to: https://github.com/organizations/${GITHUB_ORG}/settings/secrets/actions"
echo ""
echo "Add these secrets at the ORGANIZATION level:"
echo ""
echo "   AZURE_CLIENT_ID       = $APP_ID"
echo "   AZURE_TENANT_ID       = $TENANT_ID"
echo "   AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo ""
echo "============================================"
echo "📋 Federated Credentials Created"
echo "============================================"
echo ""
az ad app federated-credential list --id $APP_OBJECT_ID --query "[].{Name:name, Subject:subject}" -o table
echo ""
echo "============================================"
echo "🚀 Next Steps"
echo "============================================"
echo ""
echo "1. Configure GitHub Organization secrets (see above)"
echo "2. Re-run any failed service deployment workflows"
echo "3. All services using the reusable workflow will authenticate!"
echo ""
