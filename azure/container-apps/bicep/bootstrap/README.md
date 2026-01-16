# Bootstrap Deployment

## Purpose

This directory contains the **bootstrap deployment** that creates the foundational Azure infrastructure needed to support the Bicep registry pattern.

## Why Bootstrap?

We have a chicken-and-egg problem:
- We want to store Bicep modules in Azure Container Registry (ACR)
- We want to use Bicep modules to deploy infrastructure
- But ACR doesn't exist yet to reference modules from!

**Solution**: Bootstrap deployment uses **local module references** to create ACR. Once ACR exists, we publish modules to it, and all future deployments reference modules from ACR.

## What Gets Deployed

This bootstrap deployment creates:

1. **Resource Group**: `xshopai-shared-rg` (if it doesn't exist)
2. **Azure Container Registry**: `xshopaimodules` with:
   - SKU: Standard
   - Anonymous pull: Disabled (requires authentication)
   - Admin user: Disabled (use RBAC)
   - Public network access: Enabled
   - Zone redundancy: Disabled (cost optimization)

## Deployment Steps

### 1. Review Parameters

Edit `acr-registry.bicepparam` to customize:
- ACR name (must be globally unique)
- Location
- SKU
- Tags

### 2. Deploy Using Azure CLI

```bash
# Navigate to bootstrap directory
cd c:/gh/xshopai/infrastructure/azure/container-apps/bicep/bootstrap

# Deploy the ACR registry
az deployment sub create \
  --name "bootstrap-acr-$(date +%Y%m%d-%H%M%S)" \
  --location eastus \
  --template-file acr-registry.bicep \
  --parameters acr-registry.bicepparam
```

### 3. Verify Deployment

```bash
# Check if ACR was created
az acr show --name xshopaimodules --query "{name:name,loginServer:loginServer,sku:sku.name}" -o table

# Login to ACR
az acr login --name xshopaimodules
```

### 4. Publish Modules to ACR

After ACR is deployed, publish all modules:

```bash
cd ../modules

# Publish all 15 modules (PowerShell script)
../scripts/publish-modules.ps1 -RegistryName xshopaimodules

# Or manually for each module
az bicep publish --file resource-group.bicep --target br:xshopaimodules.azurecr.io/bicep/modules/resource-group:1.0.0
# ... (repeat for all modules)
```

### 5. Validate Module References

Test that modules can be referenced from ACR:

```bash
# Try using a module from ACR
az bicep build --file ../examples/test-acr-reference.bicep
```

## Post-Bootstrap

Once bootstrap is complete and modules are published:

1. ✅ ACR is operational
2. ✅ All 15 modules published to ACR with v1.0.0 tags
3. ✅ Module references work: `br:xshopaimodules.azurecr.io/bicep/modules/{name}:1.0.0`
4. ✅ Ready to create `environments/dev` and `environments/prod` deployments

## Future Deployments

All future deployments (dev, prod) will reference modules from ACR:

```bicep
// Instead of local reference:
module logAnalytics '../modules/log-analytics.bicep' = { ... }

// Use ACR reference:
module logAnalytics 'br:xshopaimodules.azurecr.io/bicep/modules/log-analytics:1.0.0' = { ... }
```

## Updating Bootstrap

If you need to update ACR configuration later:
1. Modify `acr-registry.bicep` or parameters
2. Re-deploy using same command
3. Bicep will update only changed resources

## Cleanup

To remove bootstrap infrastructure (⚠️ **destroys ACR and all modules**):

```bash
az group delete --name xshopai-shared-rg --yes --no-wait
```

**Note**: Only do this if you want to start completely fresh!
