// ============================================================================
// Azure Cosmos DB Module (MongoDB API)
// NoSQL database for services requiring MongoDB
// ============================================================================
//
// Platform Team Pattern:
// - This module creates only the Cosmos DB ACCOUNT
// - Individual services create their own DATABASES and COLLECTIONS
// - Services connect via credentials stored in Key Vault
//
// Services using this account:
// - user-service (Node.js/Mongoose)
// - product-service (Python/PyMongo)
// - review-service (Node.js/Mongoose)
// - cart-service (Java/Spring Data MongoDB - FUTURE)
// - notification-service (Node.js/Mongoose)
//
// ============================================================================

@description('Name of the Cosmos DB account')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Key Vault name for storing connection credentials')
param keyVaultName string = ''

@description('Enable free tier (only one per subscription, not available on internal subscriptions)')
param enableFreeTier bool = false

@description('Enable serverless capacity mode (alternative to free tier for internal subscriptions)')
param enableServerless bool = false

@description('Default consistency level')
@allowed(['Eventual', 'ConsistentPrefix', 'Session', 'BoundedStaleness', 'Strong'])
param consistencyLevel string = 'Session'

@description('Enable automatic failover')
param enableAutomaticFailover bool = false

@description('Enable multiple write locations')
param enableMultipleWriteLocations bool = false

// ============================================================================
// Resources
// ============================================================================

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: name
  location: location
  tags: tags
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: enableFreeTier && !enableServerless
    enableAutomaticFailover: enableAutomaticFailover
    enableMultipleWriteLocations: enableMultipleWriteLocations
    apiProperties: {
      serverVersion: '4.2'
    }
    consistencyPolicy: {
      defaultConsistencyLevel: consistencyLevel
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: concat([
      {
        name: 'EnableMongo'
      }
      {
        name: 'DisableRateLimitingResponses'
      }
    ], enableServerless ? [{ name: 'EnableServerless' }] : [])
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

// =============================================================================
// Key Vault Secrets (Connection Credentials)
// =============================================================================
// Services will use these to connect and create their own databases/collections

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

// Store the MongoDB connection string in Key Vault
resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'cosmos-db-connection-string'
  parent: keyVault
  properties: {
    value: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
  }
}

// Store account name for reference
resource accountNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'cosmos-db-account-name'
  parent: keyVault
  properties: {
    value: cosmosDbAccount.name
  }
}

// Store document endpoint for SDK access
resource documentEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'cosmos-db-document-endpoint'
  parent: keyVault
  properties: {
    value: cosmosDbAccount.properties.documentEndpoint
  }
}

// Store primary key for SDK access
resource primaryKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'cosmos-db-primary-key'
  parent: keyVault
  properties: {
    value: cosmosDbAccount.listKeys().primaryMasterKey
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Cosmos DB Account Resource ID')
output id string = cosmosDbAccount.id

@description('Cosmos DB Account Name')
output accountName string = cosmosDbAccount.name

@description('Cosmos DB Document Endpoint')
output documentEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('Connection string template note - actual connection string stored in Key Vault')
output connectionStringNote string = 'MongoDB connection string stored in Key Vault as cosmos-db-connection-string. Services append database name to connect.'
