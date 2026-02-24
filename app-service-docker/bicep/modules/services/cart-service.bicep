// Cart Service - Shopping cart management
// Database: Redis (in-memory state store)
// Runtime: Java 21 (Quarkus)

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

@description('Redis host')
param redisHost string

@description('RabbitMQ host')
param rabbitMQHost string

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'cart-service'
var port = 8080

resource cartService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'redis' })
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
      healthCheckPath: '/health/live'
      appSettings: [
        // Common settings
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'false' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${acrLoginServer}' }
        { name: 'DOCKER_ENABLE_CI', value: 'true' }
        { name: 'ENVIRONMENT', value: environment }
        { name: 'SERVICE_NAME', value: serviceName }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: 'InstrumentationKey=${applicationInsightsKey}' }
        { name: 'ApplicationInsightsAgent_EXTENSION_VERSION', value: '~3' }
        
        // Quarkus settings
        { name: 'QUARKUS_HTTP_PORT', value: string(port) }
        { name: 'QUARKUS_HTTP_HOST', value: '0.0.0.0' }
        
        // Redis configuration (Azure Redis uses SSL on port 6380)
        { name: 'QUARKUS_REDIS_HOSTS', value: 'rediss://:@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/redis-key/)@${redisHost}:6380' }
        { name: 'REDIS_HOST', value: redisHost }
        { name: 'REDIS_PORT', value: '6380' }
        { name: 'REDIS_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/redis-key/)' }
        { name: 'CART_STORAGE_PROVIDER', value: 'redis' }
        
        // Messaging configuration
        { name: 'MESSAGING_PROVIDER', value: 'rabbitmq' }
        { name: 'RABBITMQ_HOST', value: rabbitMQHost }
        { name: 'RABBITMQ_PORT', value: '5672' }
        { name: 'RABBITMQ_USERNAME', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/rabbitmq-user/)' }
        { name: 'RABBITMQ_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/rabbitmq-password/)' }
        { name: 'RABBITMQ_EXCHANGE', value: 'xshopai.events' }
        
        // JWT Authentication (HS256)
        { name: 'JWT_SECRET', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-secret/)' }
        
        // Service tokens
        { name: 'SERVICE_TOKEN', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/cart-service-token/)' }
        { name: 'SERVICE_TOKEN_ENABLED', value: 'true' }
        
        // Service URLs
        { name: 'PRODUCT_SERVICE_URL', value: 'https://app-product-service-${shortEnv}.azurewebsites.net' }
        { name: 'INVENTORY_SERVICE_URL', value: 'https://app-inventory-service-${shortEnv}.azurewebsites.net' }
        
        // Telemetry
        { name: 'QUARKUS_OTEL_ENABLED', value: 'false' }
        { name: 'OTEL_SERVICE_NAME', value: serviceName }
        
        // Cart-specific settings
        { name: 'CART_DEFAULT_TTL', value: '720h' }
        { name: 'CART_GUEST_TTL', value: '72h' }
        { name: 'CART_MAX_ITEMS', value: '100' }
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
