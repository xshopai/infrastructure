// Order Processor Service - Background order processing
// Database: SQL Server (shares order-db with order-service)
// Runtime: Java (Spring Boot)

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

@description('SQL Server host')
param sqlServerHost string

@description('Redis host')
param redisHost string

@description('RabbitMQ host')
param rabbitMQHost string

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'order-processor-service'
var port = 8007
var dbName = 'order-db' // Shares database with order-service

resource orderProcessorService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'sqlserver' })
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
        { name: 'SPRING_PROFILES_ACTIVE', value: environment == 'production' ? 'prod' : 'dev' }
        { name: 'SERVER_PORT', value: string(port) }
        { name: 'SERVICE_NAME', value: serviceName }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: 'InstrumentationKey=${applicationInsightsKey}' }
        
        // SQL Server settings (Spring format)
        { name: 'SPRING_DATASOURCE_URL', value: 'jdbc:sqlserver://${sqlServerHost}:1433;database=${dbName};encrypt=true;trustServerCertificate=false' }
        { name: 'SPRING_DATASOURCE_USERNAME', value: 'xshopadmin' }
        { name: 'SPRING_DATASOURCE_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/sqlserver-password/)' }
        { name: 'SPRING_DATASOURCE_DRIVER_CLASS_NAME', value: 'com.microsoft.sqlserver.jdbc.SQLServerDriver' }
        { name: 'SPRING_JPA_DATABASE_PLATFORM', value: 'org.hibernate.dialect.SQLServerDialect' }
        
        // Messaging (Spring format) - this service is a heavy consumer
        { name: 'SPRING_RABBITMQ_HOST', value: rabbitMQHost }
        { name: 'SPRING_RABBITMQ_PORT', value: '5672' }
        { name: 'SPRING_RABBITMQ_LISTENER_SIMPLE_CONCURRENCY', value: '5' }
        { name: 'SPRING_RABBITMQ_LISTENER_SIMPLE_MAX_CONCURRENCY', value: '10' }
        { name: 'SPRING_DATA_REDIS_HOST', value: redisHost }
        { name: 'SPRING_DATA_REDIS_PORT', value: '6380' }
        { name: 'SPRING_DATA_REDIS_SSL_ENABLED', value: 'true' }
        
        // Processor-specific settings
        { name: 'PROCESSOR_BATCH_SIZE', value: '50' }
        { name: 'PROCESSOR_POLL_INTERVAL_MS', value: '5000' }
        { name: 'PROCESSOR_RETRY_MAX_ATTEMPTS', value: '3' }
        { name: 'PROCESSOR_RETRY_DELAY_MS', value: '1000' }
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
        objectId: orderProcessorService.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = orderProcessorService.name
output appServiceUrl string = 'https://${orderProcessorService.properties.defaultHostName}'
output principalId string = orderProcessorService.identity.principalId
