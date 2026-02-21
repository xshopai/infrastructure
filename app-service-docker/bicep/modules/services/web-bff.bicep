// Web BFF - Backend for Frontend (API Gateway)
// Database: None (proxies to backend services)
// Runtime: Node.js (Express)

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

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'web-bff'
var port = 8014

resource webBff 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'none' })
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
        
        // Redis for caching
        { name: 'REDIS_HOST', value: redisHost }
        { name: 'REDIS_PORT', value: '6380' }
        { name: 'REDIS_SSL', value: 'true' }
        
        // JWT - BFF validates tokens before proxying
        { name: 'JWT_PUBLIC_KEY', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-public-key/)' }
        { name: 'JWT_ALGORITHM', value: 'RS256' }
        
        // Backend service URLs (internal App Service URLs)
        { name: 'AUTH_SERVICE_URL', value: 'https://app-auth-service-${shortEnv}.azurewebsites.net' }
        { name: 'USER_SERVICE_URL', value: 'https://app-user-service-${shortEnv}.azurewebsites.net' }
        { name: 'PRODUCT_SERVICE_URL', value: 'https://app-product-service-${shortEnv}.azurewebsites.net' }
        { name: 'CART_SERVICE_URL', value: 'https://app-cart-service-${shortEnv}.azurewebsites.net' }
        { name: 'ORDER_SERVICE_URL', value: 'https://app-order-service-${shortEnv}.azurewebsites.net' }
        { name: 'PAYMENT_SERVICE_URL', value: 'https://app-payment-service-${shortEnv}.azurewebsites.net' }
        { name: 'REVIEW_SERVICE_URL', value: 'https://app-review-service-${shortEnv}.azurewebsites.net' }
        { name: 'INVENTORY_SERVICE_URL', value: 'https://app-inventory-service-${shortEnv}.azurewebsites.net' }
        { name: 'NOTIFICATION_SERVICE_URL', value: 'https://app-notification-service-${shortEnv}.azurewebsites.net' }
        { name: 'CHAT_SERVICE_URL', value: 'https://app-chat-service-${shortEnv}.azurewebsites.net' }
        
        // BFF-specific settings
        { name: 'CORS_ORIGINS', value: environment == 'production' ? 'https://xshopai.com' : '*' }
        { name: 'RATE_LIMIT_WINDOW_MS', value: '60000' }
        { name: 'RATE_LIMIT_MAX_REQUESTS', value: '100' }
        { name: 'REQUEST_TIMEOUT_MS', value: '30000' }
        { name: 'CACHE_TTL_SECONDS', value: '60' }
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
        objectId: webBff.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = webBff.name
output appServiceUrl string = 'https://${webBff.properties.defaultHostName}'
output principalId string = webBff.identity.principalId
