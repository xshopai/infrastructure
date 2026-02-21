// Review Service - Product reviews and ratings
// Database: MySQL
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

@description('MySQL host')
param mysqlHost string

@description('Redis host')
param redisHost string

@description('RabbitMQ host')
param rabbitMQHost string

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'review-service'
var port = 8005
var dbName = 'review-db'

resource reviewService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'mysql' })
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
        
        // MySQL settings
        { name: 'MYSQL_HOST', value: mysqlHost }
        { name: 'MYSQL_PORT', value: '3306' }
        { name: 'MYSQL_DATABASE', value: dbName }
        { name: 'MYSQL_USER', value: 'xshopadmin' }
        { name: 'MYSQL_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/mysql-password/)' }
        { name: 'MYSQL_SSL', value: 'true' }
        
        // Messaging
        { name: 'RABBITMQ_HOST', value: rabbitMQHost }
        { name: 'RABBITMQ_PORT', value: '5672' }
        { name: 'REDIS_HOST', value: redisHost }
        { name: 'REDIS_PORT', value: '6380' }
        { name: 'REDIS_SSL', value: 'true' }
        
        // JWT - for protected endpoints
        { name: 'JWT_PUBLIC_KEY', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-public-key/)' }
        { name: 'JWT_ALGORITHM', value: 'RS256' }
        
        // Review-specific settings
        { name: 'MIN_REVIEW_LENGTH', value: '10' }
        { name: 'MAX_REVIEW_LENGTH', value: '5000' }
        { name: 'REVIEWS_PER_PAGE', value: '10' }
        { name: 'REQUIRE_PURCHASE_FOR_REVIEW', value: 'false' }
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
        objectId: reviewService.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = reviewService.name
output appServiceUrl string = 'https://${reviewService.properties.defaultHostName}'
output principalId string = reviewService.identity.principalId
