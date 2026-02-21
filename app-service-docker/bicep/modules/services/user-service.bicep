// User Service - User profile and account management
// Database: Cosmos DB (MongoDB API)
// Runtime: Node.js

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Short environment name (dev/pro)')
param shortEnv string

@description('App Service Plan ID')
param appServicePlanId string

@description('ACR login server URL')
param acrLoginServer string

@description('Key Vault name')
param keyVaultName string

@description('Application Insights instrumentation key')
param applicationInsightsKey string

@description('Cosmos DB endpoint')
param cosmosEndpoint string

@description('Redis host')
param redisHost string

@description('RabbitMQ host')
param rabbitMQHost string

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'user-service'
var port = 8002
var dbName = 'user-db'

resource userService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'cosmos' })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/${serviceName}:latest'
      alwaysOn: environment == 'production'
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        // Common settings
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'false' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${acrLoginServer}' }
        { name: 'DOCKER_ENABLE_CI', value: 'true' }
        { name: 'ENVIRONMENT', value: environment }
        { name: 'NODE_ENV', value: environment == 'production' ? 'production' : 'development' }
        { name: 'PORT', value: string(port) }
        { name: 'SERVICE_NAME', value: serviceName }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: 'InstrumentationKey=${applicationInsightsKey}' }
        
        // MongoDB (Cosmos DB) settings
        { name: 'MONGODB_URI', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/cosmos-connection-string/)' }
        { name: 'MONGODB_DATABASE', value: dbName }
        { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
        
        // Messaging
        { name: 'RABBITMQ_HOST', value: rabbitMQHost }
        { name: 'RABBITMQ_PORT', value: '5672' }
        { name: 'REDIS_HOST', value: redisHost }
        { name: 'REDIS_PORT', value: '6380' }
        { name: 'REDIS_SSL', value: 'true' }
        
        // JWT - user-service validates tokens
        { name: 'JWT_PUBLIC_KEY', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-public-key/)' }
        { name: 'JWT_ALGORITHM', value: 'RS256' }
        
        // User-specific settings
        { name: 'PROFILE_IMAGE_MAX_SIZE', value: '5242880' }
        { name: 'ADDRESS_MAX_COUNT', value: '10' }
      ]
    }
  }
}

// Grant Key Vault access
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource keyVaultAccess 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: userService.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = userService.name
output appServiceUrl string = 'https://${userService.properties.defaultHostName}'
output principalId string = userService.identity.principalId
