#!/bin/bash
# ============================================================================
# Azure OIDC Setup Script for xshopai Platform
# ============================================================================
# This script sets up Azure AD Application with federated credentials for
# GitHub Actions OIDC authentication across all xshopai repositories.
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Sufficient permissions to create Azure AD applications
#   - Access to all xshopai GitHub repositories
#
# Usage:
#   chmod +x setup-azure-oidc.sh
#   ./setup-azure-oidc.sh
# ============================================================================

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - Modify these variables as needed
# ============================================================================
LOCATION="swedencentral"           # Azure region for deployments
GITHUB_ORG="xshopai"               # GitHub organization name
APP_DISPLAY_NAME="xshopai-github-actions"  # Azure AD App name
ENVIRONMENTS=("dev" "staging" "prod")      # Deployment environments

# All service repositories that need federated credentials
SERVICE_REPOS=(
    "admin-service"
    "admin-ui"
    "audit-service"
    "auth-service"
    "cart-service"
    "chat-service"
    "customer-ui"
    "infrastructure"
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
# Step 4: Create Federated Credentials for Infrastructure Repo
# ============================================================================

echo ""
echo "🔧 Step 4: Creating federated credentials for infrastructure repository..."

# Infrastructure repo - main branch
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

# Infrastructure repo credentials
create_federated_credential \
    "infrastructure-main" \
    "repo:${GITHUB_ORG}/infrastructure:ref:refs/heads/main" \
    "Deploy from infrastructure main branch"

for env in "${ENVIRONMENTS[@]}"; do
    create_federated_credential \
        "infrastructure-env-${env}" \
        "repo:${GITHUB_ORG}/infrastructure:environment:${env}" \
        "Deploy to ${env} environment from infrastructure repo"
done

# ============================================================================
# Step 5: Create Federated Credentials for Service Repos
# ============================================================================

echo ""
echo "🔧 Step 5: Creating federated credentials for service repositories..."
echo "   This may take a few minutes..."

for repo in "${SERVICE_REPOS[@]}"; do
    if [ "$repo" == "infrastructure" ]; then
        continue  # Already handled above
    fi
    
    echo ""
    echo "   📦 Setting up: $repo"
    
    # Main branch credential
    create_federated_credential \
        "${repo}-main" \
        "repo:${GITHUB_ORG}/${repo}:ref:refs/heads/main" \
        "Deploy from ${repo} main branch"
    
    # Environment credentials
    for env in "${ENVIRONMENTS[@]}"; do
        create_federated_credential \
            "${repo}-env-${env}" \
            "repo:${GITHUB_ORG}/${repo}:environment:${env}" \
            "Deploy to ${env} environment from ${repo} repo"
    done
done

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
echo "2. Create GitHub environments (dev, staging, prod) in each repo"
echo "3. Run infrastructure deployment workflow"
echo "4. Run service deployment workflows"
echo ""
