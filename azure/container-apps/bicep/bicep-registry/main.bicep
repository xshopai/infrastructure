// ============================================================================
// Bicep Module Registry - Creates ACR for hosting reusable Bicep modules
// ============================================================================
// This template creates the shared resources needed BEFORE the CI/CD pipeline
// can publish Bicep modules. Run this ONCE to bootstrap the environment.
//
// Resources created:
// - Resource Group for shared infrastructure (using resource-group module)
// - Azure Container Registry for Bicep module storage (using acr module)
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name')
@allowed(['dev', 'prod'])
param environment string = 'prod'

@description('Azure region for resources')
param location string = 'swedencentral'

@description('Name of the Azure Container Registry for Bicep modules (must be globally unique)')
param acrName string = 'xshopaimodules'

@description('SKU for the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  purpose: 'shared-infrastructure'
  managedBy: 'bicep'
  project: 'xshopai'
}

// ============================================================================
// Variables
// ============================================================================

var resourceGroupName = 'rg-xshopai-shared-${environment}'

// ============================================================================
// Resource Group (using module)
// ============================================================================

module sharedResourceGroup '../modules/resource-group.bicep' = {
  name: 'deploy-rg-${resourceGroupName}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// ============================================================================
// Azure Container Registry for Bicep Modules (using module)
// ============================================================================

module acr '../modules/acr.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'deploy-acr-${acrName}'
  dependsOn: [sharedResourceGroup]
  params: {
    name: acrName
    location: location
    sku: acrSku
    tags: union(tags, {
      purpose: 'bicep-module-registry'
    })
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Name of the created resource group')
output resourceGroupName string = sharedResourceGroup.outputs.name

@description('Location of the resource group')
output resourceGroupLocation string = sharedResourceGroup.outputs.location

@description('Name of the Azure Container Registry')
output acrName string = acr.outputs.name

@description('Login server URL for the Azure Container Registry')
output acrLoginServer string = acr.outputs.loginServer

@description('Resource ID of the Azure Container Registry')
output acrResourceId string = acr.outputs.resourceId
