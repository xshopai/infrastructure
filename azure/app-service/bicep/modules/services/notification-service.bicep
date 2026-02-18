// Notification Service - Email and push notifications
// Database: PostgreSQL
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

@description('PostgreSQL host')
param postgresHost string

@description('Redis host')
param redisHost string

@description('RabbitMQ host')
param rabbitMQHost string

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'notification-service'
var port = 8011
var dbName = 'notification-db'

resource notificationService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'postgres' })
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
        
        // PostgreSQL settings
        { name: 'POSTGRES_HOST', value: postgresHost }
        { name: 'POSTGRES_PORT', value: '5432' }
        { name: 'POSTGRES_DATABASE', value: dbName }
        { name: 'POSTGRES_USER', value: 'xshopadmin' }
        { name: 'POSTGRES_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/postgres-password/)' }
        { name: 'POSTGRES_SSL', value: 'true' }
        
        // Messaging - notification-service is a consumer and producer
        { name: 'RABBITMQ_HOST', value: rabbitMQHost }
        { name: 'RABBITMQ_PORT', value: '5672' }
        { name: 'REDIS_HOST', value: redisHost }
        { name: 'REDIS_PORT', value: '6380' }
        { name: 'REDIS_SSL', value: 'true' }
        
        // Notification-specific settings
        { name: 'SMTP_HOST', value: '' }
        { name: 'SMTP_PORT', value: '587' }
        { name: 'SMTP_USER', value: '' }
        { name: 'SMTP_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/smtp-password/)' }
        { name: 'EMAIL_FROM', value: 'noreply@xshopai.com' }
        { name: 'NOTIFICATION_BATCH_SIZE', value: '50' }
        { name: 'RETRY_MAX_ATTEMPTS', value: '3' }
        { name: 'RETRY_DELAY_MS', value: '1000' }
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
        objectId: notificationService.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = notificationService.name
output appServiceUrl string = 'https://${notificationService.properties.defaultHostName}'
output principalId string = notificationService.identity.principalId
