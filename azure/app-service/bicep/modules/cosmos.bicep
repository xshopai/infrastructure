// Cosmos DB module (MongoDB API)
// Used by: audit-service, auth-service, user-service, product-service, inventory-service

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Short environment name (dev/pro)')
param shortEnv string

@description('Resource tags')
param tags object

@description('Key Vault name for storing connection strings')
param keyVaultName string

// Cosmos DB Account with MongoDB API
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: 'cosmos-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      { name: 'EnableMongo' }
      { name: 'EnableServerless' }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: {
        tier: 'Continuous7Days'
      }
    }
  }
}

// Databases for each service
var databases = [
  'audit-db'
  'auth-db'
  'user-db'
  'product-db'
  'inventory-db'
]

resource cosmosDatabases 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2023-11-15' = [for db in databases: {
  parent: cosmosAccount
  name: db
  properties: {
    resource: {
      id: db
    }
  }
}]

// Store connection string in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource cosmosConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cosmos-connection-string'
  properties: {
    value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
  }
}

// Outputs
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosAccountName string = cosmosAccount.name
