// ============================================================================
// Azure Service Bus Module
// Message broker for Dapr pub/sub component
// ============================================================================

@description('Name of the Service Bus namespace')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('SKU for Service Bus')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Standard'

@description('Managed Identity Principal ID for access')
param managedIdentityPrincipalId string

// ============================================================================
// Variables
// ============================================================================

// Topics for Dapr pub/sub (matching service events)
var topics = [
  'user-events'
  'product-events'
  'order-events'
  'payment-events'
  'inventory-events'
  'notification-events'
  'cart-events'
  'review-events'
  'audit-events'
]

// ============================================================================
// Resources
// ============================================================================

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Create topics (only for Standard/Premium SKU)
resource serviceBusTopics 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = [for topic in topics: if (sku != 'Basic') {
  parent: serviceBusNamespace
  name: topic
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'
    enablePartitioning: false
    enableBatchedOperations: true
  }
}]

// Default subscription for each topic (Dapr creates subscriptions dynamically)
resource defaultSubscriptions 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = [for (topic, i) in topics: if (sku != 'Basic') {
  parent: serviceBusTopics[i]
  name: 'default'
  properties: {
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    lockDuration: 'PT1M'
  }
}]

// Authorization rule for Dapr
resource daprAuthRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'dapr-auth-rule'
  properties: {
    rights: [
      'Listen'
      'Send'
      'Manage'
    ]
  }
}

// Grant Azure Service Bus Data Owner role to managed identity
resource serviceBusDataOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, managedIdentityPrincipalId, 'Azure Service Bus Data Owner')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419') // Azure Service Bus Data Owner
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Service Bus Namespace Resource ID')
output id string = serviceBusNamespace.id

@description('Service Bus Namespace Name')
output namespaceName string = serviceBusNamespace.name

@description('Service Bus Connection String')
output connectionString string = daprAuthRule.listKeys().primaryConnectionString

@description('Service Bus Endpoint')
output endpoint string = serviceBusNamespace.properties.serviceBusEndpoint
