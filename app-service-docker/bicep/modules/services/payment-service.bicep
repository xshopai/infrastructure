// Payment Service - Payment processing
// Database: SQL Server
// Runtime: .NET 8

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
var serviceName = 'payment-service'
var port = 8009
var dbName = 'payment-db'

resource paymentService 'Microsoft.Web/sites@2023-01-01' = {
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
        { name: 'ASPNETCORE_ENVIRONMENT', value: environment == 'production' ? 'Production' : 'Development' }
        { name: 'ASPNETCORE_URLS', value: 'http://+:${port}' }
        { name: 'SERVICE_NAME', value: serviceName }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: 'InstrumentationKey=${applicationInsightsKey}' }
        
        // SQL Server settings (.NET format)
        { name: 'ConnectionStrings__DefaultConnection', value: 'Server=${sqlServerHost};Database=${dbName};User Id=xshopadmin;Password=@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/sqlserver-password/);Encrypt=True;TrustServerCertificate=False' }
        
        // Messaging (.NET format)
        { name: 'RabbitMQ__Host', value: rabbitMQHost }
        { name: 'RabbitMQ__Port', value: '5672' }
        { name: 'Redis__Host', value: redisHost }
        { name: 'Redis__Port', value: '6380' }
        { name: 'Redis__Ssl', value: 'true' }
        
        // JWT
        { name: 'Jwt__PublicKey', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-public-key/)' }
        { name: 'Jwt__Algorithm', value: 'RS256' }
        
        // Payment-specific settings
        { name: 'Payment__StripeEnabled', value: 'true' }
        { name: 'Payment__StripeSecretKey', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/stripe-secret-key/)' }
        { name: 'Payment__StripeWebhookSecret', value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/stripe-webhook-secret/)' }
        { name: 'Payment__PayPalEnabled', value: 'false' }
        { name: 'Payment__RetryAttempts', value: '3' }
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
        objectId: paymentService.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

output appServiceName string = paymentService.name
output appServiceUrl string = 'https://${paymentService.properties.defaultHostName}'
output principalId string = paymentService.identity.principalId
