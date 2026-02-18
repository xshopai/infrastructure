// App Services module - 16 services
param location string
param environment string
param shortEnv string
param acrName string
param keyVaultName string
param applicationInsightsKey string
param tags object

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  sku: {
    name: environment == 'production' ? 'P1v2' : 'B1'
    tier: environment == 'production' ? 'PremiumV2' : 'Basic'
    capacity: environment == 'production' ? 2 : 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Service definitions
var services = [
  { name: 'auth-service', port: 8000 }
  { name: 'user-service', port: 8002 }
  { name: 'product-service', port: 8001 }
  { name: 'inventory-service', port: 8003 }
  { name: 'cart-service', port: 8004 }
  { name: 'review-service', port: 8005 }
  { name: 'payment-service', port: 8009 }
  { name: 'order-service', port: 8006 }
  { name: 'order-processor-service', port: 8007 }
  { name: 'notification-service', port: 8011 }
  { name: 'audit-service', port: 8010 }
  { name: 'admin-service', port: 8012 }
  { name: 'chat-service', port: 8013 }
  { name: 'web-bff', port: 8014 }
  { name: 'customer-ui', port: 3000 }
  { name: 'admin-ui', port: 3001 }
]

// Create App Services
resource appServices 'Microsoft.Web/sites@2023-01-01' = [for service in services: {
  name: 'app-${service.name}-${shortEnv}'
  location: location
  tags: union(tags, { Service: service.name })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrName}/${service.name}:latest'
      alwaysOn: environment == 'production' ? true : false
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acrName}'
        }
        {
          name: 'DOCKER_ENABLE_CI'
          value: 'true'
        }
        {
          name: 'PORT'
          value: string(service.port)
        }
        {
          name: 'NODE_ENV'
          value: environment == 'production' ? 'production' : 'development'
        }
        {
          name: 'ENVIRONMENT'
          value: environment
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${applicationInsightsKey}'
        }
        // Key Vault references (will be populated by workflow)
        {
          name: 'JWT_PRIVATE_KEY'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-private-key/)'
        }
        {
          name: 'JWT_PUBLIC_KEY'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/jwt-public-key/)'
        }
        {
          name: 'ADMIN_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/admin-password/)'
        }
        {
          name: 'MONGODB_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/mongodb-password/)'
        }
        {
          name: 'POSTGRES_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/postgres-password/)'
        }
        {
          name: 'MYSQL_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/mysql-password/)'
        }
        {
          name: 'SQLSERVER_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/sqlserver-password/)'
        }
      ]
    }
  }
}]

// Grant Key Vault access to App Services
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource keyVaultAccessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [for (service, i) in services: {
      tenantId: subscription().tenantId
      objectId: appServices[i].identity.principalId
      permissions: {
        secrets: [
          'get'
          'list'
        ]
      }
    }]
  }
}

// Outputs
output appServicePlanId string = appServicePlan.id
output appServiceNames array = [for (service, i) in services: appServices[i].name]
output appServiceUrls array = [for (service, i) in services: 'https://${appServices[i].properties.defaultHostName}']
