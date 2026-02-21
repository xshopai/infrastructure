// Azure Container Registry module
// Shared across all environments - stores Docker images for all services

@description('Azure region for ACR')
param location string

@description('Environment name')
param environment string

@description('Short environment name (dev/pro)')
param shortEnv string

@description('Resource tags')
param tags object

@description('Organization name (used in naming)')
param orgName string = 'xshopai'

@description('Pipeline platform (gh/ado)')
param pipeline string = 'gh'

// ACR name must be globally unique, alphanumeric only
var acrName = 'acr${orgName}${pipeline}${shortEnv}'

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: environment == 'production' ? 'Standard' : 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    policies: {
      retentionPolicy: {
        days: environment == 'production' ? 30 : 7
        status: 'enabled'
      }
    }
  }
}

// Outputs
output acrName string = containerRegistry.name
output acrLoginServer string = containerRegistry.properties.loginServer
output acrId string = containerRegistry.id
