# Bootstrap Infrastructure

## Overview

This directory contains the **bootstrap infrastructure** deployment for the xshopai platform. This is a **one-time deployment** that creates the foundational resources needed to store and reference Bicep modules.

## Purpose

**Problem**: We need Azure Container Registry (ACR) to store Bicep modules, but we want to use Bicep modules to create ACR.

**Solution**: Bootstrap deployment uses **local module references** to create ACR, then publishes all modules to it. Future deployments reference modules **from ACR** instead of local paths.

## What Gets Deployed

1. **Resource Group** (`xshopai-shared-{env}-rg`)
   - Shared infrastructure container

2. **Azure Container Registry** (`xshopai{env}registry`)
   - Stores Bicep modules for reuse
   - Standard SKU (supports geo-replication if needed)
   - Anonymous pull disabled (security)

3. **User-Assigned Managed Identity** (`xshopai-github-{env}-id`)
   - Used by GitHub Actions for authentication
   - Assigned `AcrPush` role on the registry

## Deployment Methods

### Option 1: GitHub Actions (Recommended)

```bash
# Navigate to GitHub repository
# Go to Actions → Bootstrap Infrastructure Deployment → Run workflow
# Select environment (dev/staging/prod)
```

**Workflow automatically**:
- ✅ Deploys bootstrap infrastructure using local modules
- ✅ Publishes all 15 Bicep modules to ACR
- ✅ Verifies module publication
- ✅ Provides summary with next steps

### Option 2: Manual Deployment (Azure CLI)

```bash
# Navigate to bootstrap directory
cd infrastructure/azure/container-apps/bicep/bootstrap

# Deploy bootstrap infrastructure
az deployment sub create \
  --name "bootstrap-dev-$(date +%Y%m%d-%H%M%S)" \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters environment=dev

# Extract ACR name from outputs
ACR_NAME=$(az deployment sub show --name <deployment-name> --query 'properties.outputs.acrName.value' -o tsv)
ACR_LOGIN_SERVER=$(az deployment sub show --name <deployment-name> --query 'properties.outputs.acrLoginServer.value' -o tsv)

echo "ACR Name: $ACR_NAME"
echo "ACR Login Server: $ACR_LOGIN_SERVER"
```

## Files

- **`main.bicep`** - Bootstrap infrastructure template (uses local module paths)
- **`main.bicepparam`** - Default parameters for dev environment
- **`BOOTSTRAP.md`** - This file

## Post-Deployment Steps

### 1. Configure GitHub Actions Federated Credentials

```bash
# Get managed identity details
az identity show \
  --name xshopai-github-dev-id \
  --resource-group xshopai-shared-dev-rg \
  --query '{clientId:clientId, principalId:principalId}' \
  -o table

# Go to Azure Portal
# Navigate to: Managed Identity → Federated credentials → Add credential
```

**Federated Credential Configuration**:
- **Scenario**: GitHub Actions deploying Azure resources
- **Organization**: `<your-github-org>`
- **Repository**: `<your-repo-name>`
- **Entity Type**: `Environment`
- **Environment Name**: `dev` (or `staging`/`prod`)
- **Name**: `github-actions-federated-credential`

### 2. Add GitHub Secrets

Navigate to **GitHub Repository → Settings → Secrets and variables → Actions**

Add these secrets:
- `AZURE_CLIENT_ID` - Managed Identity Client ID (from step 1)
- `AZURE_TENANT_ID` - Your Azure AD Tenant ID
- `AZURE_SUBSCRIPTION_ID` - Your Azure Subscription ID

```bash
# Get tenant and subscription IDs
az account show --query '{tenantId:tenantId, subscriptionId:id}' -o table
```

### 3. Verify Module Publication

```bash
# List all published modules
az acr repository list \
  --name xshopaidevregistry \
  --output table

# Show tags for specific module
az acr repository show-tags \
  --name xshopaidevregistry \
  --repository bicep/modules/container-app \
  --output table
```

## Next Steps

After bootstrap deployment completes:

1. ✅ **Phase 1 Complete** - ACR operational, modules published
2. ➡️ **Phase 2** - Deploy shared platform infrastructure (`environments/dev/`)
3. ➡️ **Phase 3** - Deploy core services (product, user, auth, cart)

See [MIGRATION-PLAN.md](../MIGRATION-PLAN.md) for complete roadmap.
