// ============================================================================
// Dev Bootstrap - Creates ACR for hosting reusable Bicep modules
// ============================================================================
// This template creates the dev-specific ACR needed for the CI/CD pipeline
// to publish Bicep modules for the dev environment.
//
// Resources created:
// - Resource Group for dev bootstrap infrastructure
// - Azure Container Registry for dev Bicep module storage
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name')
param environment string = 'dev'

@description('Azure region for resources')
param location string = 'swedencentral'

@description('Name of the Azure Container Registry for Bicep modules (must be globally unique)')
param acrName string = 'xshopaimodulesdev'

@description('SKU for the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  purpose: 'bootstrap-infrastructure'
  managedBy: 'bicep'
  project: 'xshopai'
}

// ============================================================================
// Variables
// ============================================================================

var resourceGroupName = 'rg-xshopai-${environment}'

// ============================================================================
// Resource Group (using module)
// ============================================================================

module resourceGroup '../../modules/resource-group.bicep' = {
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

module acr '../../modules/acr.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'deploy-acr-${acrName}'
  dependsOn: [resourceGroup]
  params: {
    name: acrName
    location: location
    sku: acrSku
    tags: union(tags, {
      purpose: 'bicep-module-registry'
    })
    adminUserEnabled: false
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Name of the created resource group')
output resourceGroupName string = resourceGroup.outputs.name

@description('Location of the resource group')
output resourceGroupLocation string = resourceGroup.outputs.location

@description('Name of the Azure Container Registry')
output acrName string = acr.outputs.name

@description('Login server URL for the Azure Container Registry')
output acrLoginServer string = acr.outputs.loginServer

@description('Resource ID of the Azure Container Registry')
output acrResourceId string = acr.outputs.resourceId
