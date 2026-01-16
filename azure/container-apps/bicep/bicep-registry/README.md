# Bicep Module Registry Deployment

This folder contains the Bicep templates for deploying the Azure Container Registry (ACR) that hosts reusable Bicep modules for the xshopai platform.

## Purpose

The Bicep module registry enables a modular infrastructure-as-code approach across our multi-repository microservices architecture. This deployment creates:

1. **Shared Resource Group** (`rg-xshopai-shared-prod`) - Houses cross-environment infrastructure
2. **Azure Container Registry** (`xshopaimodules`) - Stores and versions Bicep modules

## Why We Need This

In a multi-repo microservices architecture, each service needs to deploy similar Azure resources (Container Apps, databases, Key Vaults, etc.). Instead of duplicating Bicep code across repositories, we:

1. **Publish** reusable modules to this ACR
2. **Consume** modules using `br/xshopai:bicep/container-apps/{module}:{version}`
3. **Version** modules independently for controlled rollouts

## Prerequisites

- Azure CLI installed and authenticated
- Subscription-level deployment permissions
- Bicep CLI installed (comes with Azure CLI)

## Deployment

### Using GitHub Actions (Recommended)

Run the **Deploy Bicep Module Registry** workflow from GitHub Actions:
1. Go to Actions → Deploy Bicep Module Registry
2. Select environment (`prod`)
3. Set `dry_run` to `false` to deploy

### Local Deployment (Bash)

```bash
# From the infrastructure root directory
cd azure/container-apps/bicep/bicep-registry

# Preview the deployment (what-if)
az deployment sub what-if \
  --name bicep-registry-$(date +%Y%m%d-%H%M%S) \
  --location swedencentral \
  --template-file main.bicep \
  --parameters parameters.prod.json

# Deploy
az deployment sub create \
  --name bicep-registry-$(date +%Y%m%d-%H%M%S) \
  --location swedencentral \
  --template-file main.bicep \
  --parameters parameters.prod.json
```

### Local Deployment (PowerShell)

```powershell
# From the infrastructure root directory
cd azure/container-apps/bicep/bicep-registry

# Preview the deployment (what-if)
az deployment sub what-if `
  --name "bicep-registry-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters.prod.json

# Deploy
az deployment sub create `
  --name "bicep-registry-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters.prod.json
```

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| Resource Group | `rg-xshopai-shared-prod` | Shared infrastructure resources |
| Container Registry | `xshopaimodules` | Bicep module storage & versioning |

## After Deployment

Once the registry is deployed:

1. **Publish modules** - Run the **Publish Bicep Modules** workflow to upload modules to ACR
2. **Configure bicepconfig.json** - Add the registry alias to each service repository:
   ```json
   {
     "moduleAliases": {
       "br": {
         "xshopai": {
           "registry": "xshopaimodules.azurecr.io"
         }
       }
     }
   }
   ```
3. **Consume modules** - Reference modules in your Bicep files:
   ```bicep
   module containerApp 'br/xshopai:bicep/container-apps/container-app:v1.0.0' = {
     name: 'container-app'
     params: {
       name: 'my-service'
       // ...
     }
   }
   ```

## Outputs

The deployment outputs:

| Output | Description | Example |
|--------|-------------|---------|
| `resourceGroupName` | Shared resource group name | `rg-xshopai-shared-prod` |
| `acrName` | ACR name | `xshopaimodules` |
| `acrLoginServer` | ACR login server URL | `xshopaimodules.azurecr.io` |
| `acrResourceId` | Full resource ID of the ACR | `/subscriptions/.../xshopaimodules` |

## Idempotent

This deployment is idempotent - running it multiple times will not create duplicate resources. It will update existing resources if parameters change.

## Related Files

- [../modules/](../modules/) - Bicep modules published to this registry
- [../../workflows/publish-bicep-modules.yml](../../../../.github/workflows/publish-bicep-modules.yml) - Workflow to publish modules
- [../../workflows/deploy-bicep-registry.yml](../../../../.github/workflows/deploy-bicep-registry.yml) - This deployment workflow
