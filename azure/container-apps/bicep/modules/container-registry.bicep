// ============================================================================
// Azure Container Registry Module
// Stores Docker images for Container Apps
// ============================================================================

@description('Name of the Container Registry')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('SKU for the registry')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

@description('Managed Identity Principal ID for pull access')
param managedIdentityPrincipalId string

@description('Enable admin user')
param adminUserEnabled bool = false

// ============================================================================
// Resources
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'
    policies: {
      retentionPolicy: {
        status: sku == 'Premium' ? 'enabled' : 'disabled'
        days: 30
      }
    }
  }
}

// Grant AcrPull role to managed identity
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Container Registry Resource ID')
output id string = containerRegistry.id

@description('Container Registry Name')
output name string = containerRegistry.name

@description('Container Registry Login Server')
output loginServer string = containerRegistry.properties.loginServer
