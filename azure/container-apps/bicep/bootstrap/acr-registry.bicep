// ============================================================================
// Bootstrap Deployment: Azure Container Registry for Bicep Modules
// ============================================================================
// Purpose: Creates ACR registry to store Bicep modules using IaC approach
// Note: Uses LOCAL module references (not ACR) to avoid chicken-and-egg problem
// ============================================================================

targetScope = 'subscription'

// Parameters
@description('Name of the Azure Container Registry (must be globally unique, 5-50 alphanumeric characters)')
@minLength(5)
@maxLength(50)
param registryName string

@description('Azure region for the registry')
param location string = 'eastus'

@description('Resource group name for the registry')
param resourceGroupName string = 'xshopai-shared-rg'

@description('ACR SKU - Basic, Standard, or Premium')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Standard'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Shared'
  ManagedBy: 'Bicep'
  Purpose: 'Bicep Module Registry'
  Project: 'xshopai'
}

@description('Enable anonymous pull access (not recommended for production)')
param enableAnonymousPull bool = false

@description('Enable admin user (not recommended, use RBAC instead)')
param enableAdminUser bool = false

@description('Enable public network access')
param publicNetworkAccess bool = true

@description('Enable zone redundancy (Premium SKU only)')
param enableZoneRedundancy bool = false

// ============================================================================
// Resource Group
// ============================================================================
// Use LOCAL module reference (not ACR, since ACR doesn't exist yet)
module resourceGroup '../modules/resource-group.bicep' = {
  name: 'rg-${registryName}-deployment'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// ============================================================================
// Azure Container Registry
// ============================================================================
// Deploy ACR using inline Bicep (not a module) to avoid circular dependency
module acr 'acr-resource.bicep' = {
  name: 'acr-${registryName}-deployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    registryName: registryName
    location: location
    sku: sku
    tags: tags
    enableAnonymousPull: enableAnonymousPull
    enableAdminUser: enableAdminUser
    publicNetworkAccess: publicNetworkAccess
    enableZoneRedundancy: enableZoneRedundancy
  }
  dependsOn: [
    resourceGroup
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the Azure Container Registry')
output registryName string = acr.outputs.registryName

@description('The login server URL for the ACR')
output loginServer string = acr.outputs.loginServer

@description('The resource ID of the ACR')
output registryId string = acr.outputs.registryId

@description('The resource group name where ACR is deployed')
output resourceGroupName string = resourceGroupName

@description('Example module reference pattern')
output moduleReferencePattern string = 'br:${acr.outputs.loginServer}/bicep/modules/{module-name}:{version}'

@description('Example: Reference container-app module')
output exampleModuleReference string = 'br:${acr.outputs.loginServer}/bicep/modules/container-app:1.0.0'
