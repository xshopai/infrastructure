// ============================================================================
// Dapr Components Module
// Configures Dapr building blocks for Container Apps Environment
// ============================================================================

@description('Name of the Container Apps Environment')
param containerAppsEnvName string

@description('Service Bus connection string')
@secure()
param serviceBusConnectionString string

@description('Redis host name')
param redisHost string

@description('Redis password')
@secure()
param redisPassword string

@description('Key Vault name')
param keyVaultName string

@description('Managed Identity Client ID')
param managedIdentityClientId string

// ============================================================================
// Resources
// ============================================================================

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' existing = {
  name: containerAppsEnvName
}

// ============================================================================
// Pub/Sub Component - Azure Service Bus
// ============================================================================

resource pubsubComponent 'Microsoft.App/managedEnvironments/daprComponents@2023-11-02-preview' = {
  parent: containerAppsEnv
  name: 'pubsub'
  properties: {
    componentType: 'pubsub.azure.servicebus.topics'
    version: 'v1'
    metadata: [
      {
        name: 'connectionString'
        secretRef: 'service-bus-connection-string'
      }
      {
        name: 'consumerID'
        value: '{podName}'
      }
      {
        name: 'maxActiveMessages'
        value: '100'
      }
      {
        name: 'maxConcurrentHandlers'
        value: '10'
      }
      {
        name: 'lockRenewalInSec'
        value: '30'
      }
      {
        name: 'maxDeliveryCount'
        value: '10'
      }
    ]
    secrets: [
      {
        name: 'service-bus-connection-string'
        value: serviceBusConnectionString
      }
    ]
    scopes: [
      'user-service'
      'product-service'
      'order-service'
      'payment-service'
      'inventory-service'
      'notification-service'
      'cart-service'
      'review-service'
      'audit-service'
      'auth-service'
      'admin-service'
      'order-processor-service'
    ]
  }
}

// ============================================================================
// State Store Component - Azure Redis Cache
// ============================================================================

resource stateStoreComponent 'Microsoft.App/managedEnvironments/daprComponents@2023-11-02-preview' = {
  parent: containerAppsEnv
  name: 'statestore'
  properties: {
    componentType: 'state.redis'
    version: 'v1'
    metadata: [
      {
        name: 'redisHost'
        value: '${redisHost}:6380'
      }
      {
        name: 'redisPassword'
        secretRef: 'redis-password'
      }
      {
        name: 'enableTLS'
        value: 'true'
      }
      {
        name: 'actorStateStore'
        value: 'true'
      }
      {
        name: 'keyPrefix'
        value: 'xshopai'
      }
    ]
    secrets: [
      {
        name: 'redis-password'
        value: redisPassword
      }
    ]
    scopes: [
      'user-service'
      'product-service'
      'order-service'
      'cart-service'
      'auth-service'
    ]
  }
}

// ============================================================================
// Binding Component - Cosmos DB (for document storage)
// Note: Uses Key Vault secret store reference for connection string
// ============================================================================

resource cosmosDbBinding 'Microsoft.App/managedEnvironments/daprComponents@2023-11-02-preview' = {
  parent: containerAppsEnv
  name: 'cosmos-binding'
  properties: {
    componentType: 'bindings.azure.cosmosdb'
    version: 'v1'
    metadata: [
      {
        name: 'url'
        secretRef: 'cosmos-db-connection-string'
      }
      {
        name: 'database'
        value: 'xshopai'
      }
      {
        name: 'collection'
        value: 'events'
      }
    ]
    secretStoreComponent: 'secretstore'
    scopes: [
      'audit-service'
    ]
  }
  dependsOn: [
    secretStoreComponent
  ]
}

// ============================================================================
// Secret Store Component - Azure Key Vault
// ============================================================================

resource secretStoreComponent 'Microsoft.App/managedEnvironments/daprComponents@2023-11-02-preview' = {
  parent: containerAppsEnv
  name: 'secretstore'
  properties: {
    componentType: 'secretstores.azure.keyvault'
    version: 'v1'
    metadata: [
      {
        name: 'vaultName'
        value: keyVaultName
      }
      {
        name: 'azureClientId'
        value: managedIdentityClientId
      }
    ]
    scopes: [
      'user-service'
      'product-service'
      'order-service'
      'payment-service'
      'inventory-service'
      'notification-service'
      'cart-service'
      'review-service'
      'audit-service'
      'auth-service'
      'admin-service'
      'web-bff'
    ]
  }
}

// ============================================================================
// Configuration Store Component - Azure Redis
// ============================================================================

resource configStoreComponent 'Microsoft.App/managedEnvironments/daprComponents@2023-11-02-preview' = {
  parent: containerAppsEnv
  name: 'configstore'
  properties: {
    componentType: 'configuration.redis'
    version: 'v1'
    metadata: [
      {
        name: 'redisHost'
        value: '${redisHost}:6380'
      }
      {
        name: 'redisPassword'
        secretRef: 'redis-password-config'
      }
      {
        name: 'enableTLS'
        value: 'true'
      }
    ]
    secrets: [
      {
        name: 'redis-password-config'
        value: redisPassword
      }
    ]
    scopes: [
      'web-bff'
      'admin-service'
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Pub/Sub Component Name')
output pubsubComponentName string = pubsubComponent.name

@description('State Store Component Name')
output stateStoreComponentName string = stateStoreComponent.name

@description('Secret Store Component Name')
output secretStoreComponentName string = secretStoreComponent.name
