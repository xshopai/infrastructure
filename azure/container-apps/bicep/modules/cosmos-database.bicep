// ============================================================================
// Azure Cosmos DB Module
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Cosmos DB account')
param name string

@description('Azure region for deployment. Default: Sweden Central')
param location string = 'swedencentral'

@description('API type for the Cosmos DB account')
@allowed([
  'MongoDB'
  'Sql'
  'Cassandra'
  'Gremlin'
  'Table'
])
param apiType string = 'MongoDB'

@description('Enable serverless capacity mode')
param serverless bool = true

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var capabilities = apiType == 'MongoDB' ? [
  { name: 'EnableMongo' }
  { name: 'EnableServerless' }
] : serverless ? [
  { name: 'EnableServerless' }
] : []

// ============================================================================
// Resources
// ============================================================================

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: name
  location: location
  kind: apiType == 'MongoDB' ? 'MongoDB' : 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: capabilities
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

// ============================================================================
// Outputs
// ============================================================================

@description('The connection string for the Cosmos DB account')
output connectionString string = cosmos.listConnectionStrings().connectionStrings[0].connectionString

@description('The resource ID of the Cosmos DB account')
output resourceId string = cosmos.id
