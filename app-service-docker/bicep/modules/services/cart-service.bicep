// Cart Service - Shopping cart management
// Database: SQL Server
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
var serviceName = 'cart-service'
var port = 8004
var dbName = 'cart-db'

resource cartService 'Microsoft.Web/sites@2023-01-01' = {
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
        
        // Messaging (Spring format)
        { name: 'SPRING_RABBITMQ_HOST', value: rabbitMQHost }
        { name: 'SPRING_RABBITMQ_PORT', value: '5672' }
        { name: 'SPRING_DATA_REDIS_HOST', value: redisHost }
        { name: 'SPRING_DATA_REDIS_PORT', value: '6380' }
        { name: 'SPRING_DATA_REDIS_SSL_ENABLED', value: 'true' }
        
        // JWT
        { name: 'JWT_PUBLIC_KEY', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-public-key/)' }
        { name: 'JWT_ALGORITHM', value: 'RS256' }
        
        // Cart-specific settings
        { name: 'CART_EXPIRATION_HOURS', value: '72' }
        { name: 'CART_MAX_ITEMS', value: '100' }
        { name: 'CART_SESSION_ENABLED', value: 'true' }
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
        objectId: cartService.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = cartService.name
output appServiceUrl string = 'https://${cartService.properties.defaultHostName}'
output principalId string = cartService.identity.principalId
