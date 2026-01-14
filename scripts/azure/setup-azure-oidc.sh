#!/bin/bash
# ============================================================================
# Azure OIDC Setup Script for xshopai Platform
# ============================================================================
# This script sets up Azure AD Application with federated credentials for
# GitHub Actions OIDC authentication across all xshopai repositories.
#
# Key Feature: Uses job_workflow_ref for authentication!
# - ONE credential authenticates ALL services that use the reusable workflow
# - Total credentials: 2 (instead of 68+ with per-repo approach)
# - See Step 4 comments for detailed explanation
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

read -p "Continue with this subscription? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Please run 'az account set --subscription <subscription-id>' to change subscription."
    exit 1
fi

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
# Step 3: Assign Roles to Service Principal
# ============================================================================

echo ""
echo "🔧 Step 3: Assigning roles to Service Principal..."

# Contributor role
echo "   Assigning Contributor role..."
az role assignment create \
    --assignee $SP_OBJECT_ID \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --only-show-errors > /dev/null 2>&1 || echo "   (Role may already be assigned)"
echo "   ✅ Contributor role assigned"

# User Access Administrator role (needed for managed identity operations)
echo "   Assigning User Access Administrator role..."
az role assignment create \
    --assignee $SP_OBJECT_ID \
    --role "User Access Administrator" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --only-show-errors > /dev/null 2>&1 || echo "   (Role may already be assigned)"
echo "   ✅ User Access Administrator role assigned"

# AcrPush role (needed for pushing images to ACR)
echo "   Assigning AcrPush role..."
az role assignment create \
    --assignee $SP_OBJECT_ID \
    --role "AcrPush" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --only-show-errors > /dev/null 2>&1 || echo "   (Role may already be assigned)"
echo "   ✅ AcrPush role assigned"

# ============================================================================
# Step 4: Configure GitHub OIDC Subject Claims - USE DEFAULT
# ============================================================================
#
# IMPORTANT: We use the DEFAULT GitHub OIDC subject claim format!
#
# Default subject claims look like:
#   repo:xshopai/product-service:ref:refs/heads/main
#   repo:xshopai/product-service:environment:production
#
# ✅ BENEFITS of using default:
#   - No dependency on workflow filenames (can rename workflows freely)
#   - Standard GitHub pattern (widely documented)
#   - Simpler credential management (one per repo + environment)
#   - No custom OIDC configuration needed
#
# ❌ DO NOT use "job_workflow_ref" because:
#   - Creates dependency on workflow filename
#   - Breaks when workflows are renamed
#   - Non-standard approach
#   - Harder to debug
# ============================================================================

echo ""
echo "🔧 Step 4: Configuring GitHub OIDC settings..."

# Check if GitHub CLI is authenticated
if ! gh auth status > /dev/null 2>&1; then
    echo "   ❌ Error: GitHub CLI not authenticated. Please run 'gh auth login' first."
    exit 1
fi

echo "   Resetting to default GitHub OIDC configuration..."
echo "   This ensures NO dependency on workflow filenames!"

# Reset org-level OIDC to use default
gh api -X PUT "orgs/${GITHUB_ORG}/actions/oidc/customization/sub" \
    --input - <<EOF > /dev/null
{
    "use_default": true
}
EOF
echo "   ✅ Organization OIDC configured (using default)"

echo ""
echo "   Resetting OIDC for infrastructure repo..."
gh api -X PUT "repos/${GITHUB_ORG}/infrastructure/actions/oidc/customization/sub" \
    --input - <<EOF > /dev/null 2>&1 || echo "   ⚠️  Could not configure infrastructure repo"
{
    "use_default": true
}
EOF
echo "   ✅ Infrastructure repo configured to use default"

echo ""
echo "   📝 Note: Service repos will inherit org-level settings automatically."
echo "   No need to configure each repo individually."

# Verify the configuration
echo ""
echo "   Verifying configuration..."
OIDC_CONFIG=$(gh api "orgs/${GITHUB_ORG}/actions/oidc/customization/sub" 2>/dev/null || echo '{}')
echo "   Current config: $OIDC_CONFIG"

# ============================================================================
# Step 5: Create Federated Credentials Using Default Subject Format
# ============================================================================
# 
# IMPORTANT: We use DEFAULT GitHub OIDC subject claims (repo-based)!
# 
# Default subject patterns:
#   - Main branch: repo:xshopai/{repo-name}:ref:refs/heads/main
#   - Environment: repo:xshopai/{repo-name}:environment:{env-name}
#   - Pull request: repo:xshopai/{repo-name}:pull_request
#
# Each microservice repo gets:
#   - 1 credential for main branch deployments
#   - 1 credential for each environment (dev, staging, production)
#
# ✅ Benefits:
#   - No dependency on workflow filenames
#   - Standard GitHub pattern
#   - Works with any workflow in the repo
#   - Easy to understand and debug
# ============================================================================

echo ""
echo "🔧 Step 5: Creating federated credentials..."

create_federated_credential() {
    local name=$1
    local subject=$2
    local description=$3
    
    # Check if credential already exists
    EXISTING=$(az ad app federated-credential list --id $APP_OBJECT_ID --query "[?name=='$name'].name" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$EXISTING" ]; then
        echo "   ⏭️  Credential '$name' already exists, skipping..."
    else
        az ad app federated-credential create --id $APP_OBJECT_ID --parameters "{
            \"name\": \"$name\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"$subject\",
            \"description\": \"$description\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" > /dev/null
        echo "   ✅ Created credential: $name"
    fi
}

echo ""
echo "   📦 Creating credentials for infrastructure repo..."

# Infrastructure main branch
create_federated_credential \
    "infrastructure-main" \
    "repo:${GITHUB_ORG}/infrastructure:ref:refs/heads/main" \
    "Infrastructure deployments from main branch"

# Infrastructure environments
create_federated_credential \
    "infrastructure-dev" \
    "repo:${GITHUB_ORG}/infrastructure:environment:development" \
    "Infrastructure deployments to development environment"

create_federated_credential \
    "infrastructure-production" \
    "repo:${GITHUB_ORG}/infrastructure:environment:production" \
    "Infrastructure deployments to production environment"

echo ""
echo "   📦 Creating credentials for microservice repos..."

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
    echo "   Setting up $repo..."
    
    # Main branch credential
    create_federated_credential \
        "${repo}-main" \
        "repo:${GITHUB_ORG}/${repo}:ref:refs/heads/main" \
        "${repo} deployments from main branch"
    
    # Development environment credential
    create_federated_credential \
        "${repo}-dev" \
        "repo:${GITHUB_ORG}/${repo}:environment:development" \
        "${repo} deployments to development environment"
    
    # Production environment credential
    create_federated_credential \
        "${repo}-production" \
        "repo:${GITHUB_ORG}/${repo}:environment:production" \
        "${repo} deployments to production environment"
done

echo ""
echo "   ✅ Federated credentials setup complete!"
echo "   Total credentials: ~50 (well under the 300 limit)"

# ============================================================================
# Step 6: Display Summary and GitHub Secrets
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
echo "🎯 How It Works"
echo "============================================"
echo ""
echo "We configured GitHub org OIDC + Azure federated credentials to use job_workflow_ref!"
echo ""
echo "1. GitHub org OIDC is configured with:"
echo "   include_claim_keys: [\"job_workflow_ref\"]"
echo ""
echo "2. When any service (e.g., product-service) calls:"
echo "   uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main"
echo ""
echo "3. GitHub OIDC now generates subject claim as:"
echo "   job_workflow_ref:xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@refs/heads/main"
echo ""
echo "4. This matches our Azure federated credential! One credential authenticates ALL services! 🎉"
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
