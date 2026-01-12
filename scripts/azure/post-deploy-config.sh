#!/bin/bash
# ============================================================================
# Azure Infrastructure Post-Deployment Configuration Script
# ============================================================================
# This script runs AFTER the infrastructure is deployed via GitHub Actions
# to configure settings that can't be done via Bicep.
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Infrastructure already deployed
#
# Usage:
#   chmod +x post-deploy-config.sh
#   ./post-deploy-config.sh dev     # For dev environment
#   ./post-deploy-config.sh staging # For staging environment
#   ./post-deploy-config.sh prod    # For production environment
# ============================================================================

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - Modify these variables as needed
# ============================================================================
LOCATION="swedencentral"           # Azure region (must match infrastructure deployment)
PROJECT_NAME="xshopai"             # Project name prefix for resources
ENVIRONMENT=${1:-dev}              # Environment: dev, staging, or prod

# Validate environment parameter
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "❌ Error: Invalid environment. Use: dev, staging, or prod"
    echo "Usage: ./post-deploy-config.sh <environment>"
    exit 1
fi

# Resource naming
RESOURCE_GROUP="rg-${PROJECT_NAME}-${ENVIRONMENT}"
UNIQUE_SUFFIX=$(az group show --name $RESOURCE_GROUP --query tags.uniqueSuffix -o tsv 2>/dev/null || echo "")

if [ -z "$UNIQUE_SUFFIX" ]; then
    echo "❌ Error: Could not find unique suffix. Is the infrastructure deployed?"
    exit 1
fi

ACR_NAME="${PROJECT_NAME}${ENVIRONMENT}${UNIQUE_SUFFIX}acr"

echo "============================================"
echo "Post-Deployment Configuration"
echo "============================================"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Resource Group: $RESOURCE_GROUP"
echo "ACR Name: $ACR_NAME"
echo ""

# ============================================================================
# Step 1: Enable ACR Admin User
# ============================================================================
# Required for GitHub Actions to push images using username/password auth
# Alternative: Use managed identity, but this requires more complex setup

echo "🔧 Step 1: Enabling ACR Admin User..."

az acr update \
    --name $ACR_NAME \
    --admin-enabled true \
    --output none

echo "   ✅ ACR Admin User enabled"

# ============================================================================
# Step 2: Configure ACR Firewall (if needed)
# ============================================================================
# Uncomment if you need to restrict ACR access to specific networks

# echo "🔧 Step 2: Configuring ACR network rules..."
# az acr update \
#     --name $ACR_NAME \
#     --default-action Allow \
#     --output none
# echo "   ✅ ACR network rules configured"

# ============================================================================
# Step 3: Display ACR Credentials
# ============================================================================

echo ""
echo "============================================"
echo "📋 ACR Credentials"
echo "============================================"

ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer -o tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)

echo ""
echo "Login Server: $ACR_LOGIN_SERVER"
echo "Username: $ACR_USERNAME"
echo "Password: $ACR_PASSWORD"
echo ""
echo "To login manually:"
echo "   docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME -p '$ACR_PASSWORD'"
echo ""

# ============================================================================
# Step 4: Verify Container Apps Environment
# ============================================================================

CAE_NAME="cae-${PROJECT_NAME}-${ENVIRONMENT}"

echo "🔧 Step 4: Verifying Container Apps Environment..."

CAE_STATUS=$(az containerapp env show \
    --name $CAE_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound")

if [ "$CAE_STATUS" == "Succeeded" ]; then
    echo "   ✅ Container Apps Environment is healthy"
else
    echo "   ⚠️  Container Apps Environment status: $CAE_STATUS"
fi

# ============================================================================
# Step 5: List Deployed Container Apps
# ============================================================================

echo ""
echo "🔧 Step 5: Listing Container Apps..."

az containerapp list \
    --resource-group $RESOURCE_GROUP \
    --query "[].{Name:name, Status:properties.provisioningState, FQDN:properties.configuration.ingress.fqdn}" \
    -o table

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "============================================"
echo "✅ Post-Deployment Configuration Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Deploy services using their GitHub Actions workflows"
echo "2. Verify services are accessible via their FQDNs"
echo "3. Configure custom domains if needed"
echo ""
