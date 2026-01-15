// ============================================================================
// Reusable Cosmos DB SQL Database Module
// Version: 1.0.0
// Description: Creates a database on existing Cosmos DB account
// ============================================================================

@description('Name of the database to create')
param databaseName string

@description('Name of the existing Cosmos DB account')
param cosmosAccountName string

@description('Throughput (RU/s) for the database (400-1000000). Use 0 for serverless.')
param throughput int = 400

@description('Enable autoscale')
param enableAutoscale bool = false

@description('Maximum autoscale throughput (RU/s) - only used if enableAutoscale is true')
param maxAutoscaleThroughput int = 4000

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// Reference to existing Cosmos DB Account
// ============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

// ============================================================================
// Cosmos DB SQL Database
// ============================================================================

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: databaseName
    }
    options: enableAutoscale ? {
      autoscaleSettings: {
        maxThroughput: maxAutoscaleThroughput
      }
    } : (throughput > 0 ? {
      throughput: throughput
    } : {})
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Database resource ID')
output databaseId string = cosmosDatabase.id

@description('Database name')
output databaseName string = cosmosDatabase.name

@description('Cosmos DB account name')
output cosmosAccountName string = cosmosAccount.name

@description('Cosmos DB account endpoint')
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint

@description('Cosmos DB account connection string (read-only)')
output connectionString string = listConnectionStrings(cosmosAccount.id, '2023-04-15').connectionStrings[0].connectionString
