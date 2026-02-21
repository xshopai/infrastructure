// App Service Plan module
// Defines the compute resources for hosting web apps

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Short environment name (dev/pro)')
param shortEnv string

@description('Resource tags')
param tags object

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  sku: {
    name: environment == 'production' ? 'P1v2' : 'B1'
    tier: environment == 'production' ? 'PremiumV2' : 'Basic'
    capacity: environment == 'production' ? 2 : 1
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux
  }
}

// Outputs
output planId string = appServicePlan.id
output planName string = appServicePlan.name
