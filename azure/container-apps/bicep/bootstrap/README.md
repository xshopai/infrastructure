# Bootstrap Infrastructure Deployment

This folder contains the Bicep templates for bootstrapping the shared infrastructure needed before the CI/CD pipeline can operate.

## Purpose

The bootstrap deployment creates foundational resources that must exist BEFORE the main CI/CD pipelines can run:

1. **Shared Resource Group** (`rg-xshopai-shared-prod`) - Houses cross-environment resources
2. **Azure Container Registry** (`xshopaimodules`) - Stores Bicep modules for reuse

## Prerequisites

- Azure CLI installed and authenticated
- Subscription-level deployment permissions
- Bicep CLI installed (comes with Azure CLI)

## Deployment

### One-Time Bootstrap (First Time Setup)

```bash
# From the infrastructure root directory
cd azure/container-apps/bicep/bootstrap

# Preview the deployment
az deployment sub what-if \
  --name bootstrap-$(date +%Y%m%d-%H%M%S) \
  --location swedencentral \
  --template-file main.bicep \
  --parameters parameters.prod.json

# Deploy
az deployment sub create \
  --name bootstrap-$(date +%Y%m%d-%H%M%S) \
  --location swedencentral \
  --template-file main.bicep \
  --parameters parameters.prod.json
```

### PowerShell (Windows)

```powershell
# From the infrastructure root directory
cd azure/container-apps/bicep/bootstrap

# Preview the deployment
az deployment sub what-if `
  --name "bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters.prod.json

# Deploy
az deployment sub create `
  --name "bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters.prod.json
```

## What Gets Created

| Resource | Name | Purpose |
|----------|------|---------|
| Resource Group | `rg-xshopai-shared-prod` | Shared infrastructure resources |
| Container Registry | `xshopaimodules` | Bicep module storage |

## After Bootstrap

Once the bootstrap is complete:

1. The GitHub Actions workflow can publish Bicep modules to ACR
2. Service deployments can reference modules using `br/xshopai:bicep/container-apps/{module}:{version}`
3. You can proceed with deploying individual services

## Outputs

The deployment outputs:
- `resourceGroupName` - Name of the shared resource group
- `acrName` - Name of the ACR
- `acrLoginServer` - ACR login server URL (e.g., `xshopaimodules.azurecr.io`)
- `acrResourceId` - Full resource ID of the ACR

## Idempotent

This deployment is idempotent - running it multiple times will not create duplicate resources. It will update existing resources if parameters change.
