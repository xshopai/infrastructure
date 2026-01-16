// ============================================================================
// Azure Container Registry Module
// ============================================================================
// Creates an Azure Container Registry for container images and Bicep modules
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Azure Container Registry (must be globally unique)')
@minLength(5)
@maxLength(50)
param name string

@description('Azure region for the ACR. Default: Sweden Central')
param location string = 'swedencentral'

@description('SKU for the Azure Container Registry')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Enable admin user for the registry')
param adminUserEnabled bool = false

@description('Enable anonymous pull for public images')
param anonymousPullEnabled bool = false

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    anonymousPullEnabled: anonymousPullEnabled
    publicNetworkAccess: 'Enabled'
    policies: {
      retentionPolicy: {
        status: sku == 'Premium' ? 'enabled' : 'disabled'
        days: sku == 'Premium' ? 30 : 0
      }
    }
  }
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the container registry')
output name string = acr.name

@description('The login server URL')
output loginServer string = acr.properties.loginServer

@description('The resource ID of the container registry')
output resourceId string = acr.id
