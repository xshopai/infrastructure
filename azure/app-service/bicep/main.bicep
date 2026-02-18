// Main Bicep template for xshopai App Service infrastructure
targetScope = 'subscription'

@description('Environment name (development or production)')
@allowed([
  'development'
  'production'
])
param environment string = 'development'

@description('Azure region for all resources')
param location string = 'eastus'

@description('Container Registry name (passed from GitHub secrets)')
param acrName string

// Variables
var shortEnv = substring(environment, 0, 3)
var resourceGroupName = 'rg-xshopai-gh-${environment}'
var tags = {
  Environment: environment
  Project: 'xshopai'
  ManagedBy: 'Bicep'
  DeployedBy: 'GitHub Actions'
}

// Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy monitoring first (needed by other resources)
module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    tags: tags
  }
}

// Deploy Key Vault
module keyVault './modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    tags: tags
  }
}

// Deploy databases
module databases './modules/databases.bicep' = {
  name: 'databases-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    keyVaultName: keyVault.outputs.keyVaultName
    tags: tags
  }
}

// Deploy Redis Cache
module redis './modules/redis.bicep' = {
  name: 'redis-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    tags: tags
  }
}

// Deploy RabbitMQ Container Instance
module rabbitmq './modules/rabbitmq.bicep' = {
  name: 'rabbitmq-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    tags: tags
  }
}

// Deploy App Services
module appServices './modules/app-services.bicep' = {
  name: 'app-services-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    acrName: acrName
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
  }
  dependsOn: [
    databases
    redis
    rabbitmq
  ]
}

// Outputs
output resourceGroupName string = resourceGroupName
output keyVaultName string = keyVault.outputs.keyVaultName
output appInsightsName string = monitoring.outputs.appInsightsName
output rabbitMQHost string = rabbitmq.outputs.rabbitMQHost
output redisHost string = redis.outputs.redisHost
