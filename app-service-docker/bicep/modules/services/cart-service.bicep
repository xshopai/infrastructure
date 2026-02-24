// Cart Service - Shopping cart management
// Database: Redis (in-memory state store)
// Runtime: Node.js 20 (TypeScript/Express)

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
var port = 8008

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
      healthCheckPath: '/health'
      appSettings: [
        // Common settings
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'false' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${acrLoginServer}' }
        { name: 'DOCKER_ENABLE_CI', value: 'true' }
        { name: 'ENVIRONMENT', value: environment }
        { name: 'SERVICE_NAME', value: serviceName }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: 'InstrumentationKey=${applicationInsightsKey}' }
        
        // Node.js settings
        { name: 'PORT', value: string(port) }
        { name: 'HOST', value: '0.0.0.0' }
        { name: 'NODE_ENV', value: environment == 'production' ? 'production' : 'development' }
        { name: 'SERVICE_VERSION', value: '1.0.0' }
        
        // Service Invocation Mode (http for Azure without Dapr)
        { name: 'SERVICE_INVOCATION_MODE', value: 'http' }
        
        // Redis configuration (Azure Redis uses SSL on port 6380)
        { name: 'REDIS_URL', value: 'rediss://${redisHost}:6380' }
        { name: 'REDIS_HOST', value: redisHost }
        { name: 'REDIS_PORT', value: '6380' }
        { name: 'REDIS_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/redis-key/)' }
        { name: 'REDIS_TLS', value: 'true' }
        
        // Messaging configuration
        { name: 'MESSAGING_PROVIDER', value: 'rabbitmq' }
        { name: 'RABBITMQ_URL', value: 'amqp://${rabbitMQHost}:5672' }
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
        
        // CORS configuration
        { name: 'CORS_ALLOWED_ORIGINS', value: '*' }
        
        // Telemetry
        { name: 'OTEL_TRACES_EXPORTER', value: 'azure' }
        { name: 'OTEL_SERVICE_NAME', value: serviceName }
        { name: 'ENABLE_TRACING', value: 'true' }
        
        // Cart-specific settings
        { name: 'CART_TTL_DAYS', value: '30' }
        { name: 'GUEST_CART_TTL_DAYS', value: '7' }
        { name: 'CART_MAX_ITEMS', value: '50' }
        { name: 'CART_MAX_ITEM_QUANTITY', value: '99' }
        
        // Logging
        { name: 'LOG_LEVEL', value: environment == 'production' ? 'info' : 'debug' }
        { name: 'LOG_FORMAT', value: 'json' }
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
