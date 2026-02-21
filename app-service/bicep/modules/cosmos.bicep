// =============================================================================
// Cosmos DB - MongoDB API 4.2 (Session consistency)
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

@description('Enable automatic failover')
param enableAutomaticFailover bool = true

@description('Server version for MongoDB API')
@allowed(['4.0', '4.2', '5.0', '6.0'])
param serverVersion string = '4.2'

// =============================================================================
// Variables
// =============================================================================

var cosmosAccountName = 'cosmos-${resourcePrefix}'

// =============================================================================
// Resources
// =============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    apiProperties: {
      serverVersion: serverVersion
    }
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    enableAutomaticFailover: enableAutomaticFailover
    disableKeyBasedMetadataWriteAccess: false
    publicNetworkAccess: 'Enabled'
    capabilities: [
      {
        name: 'EnableMongo'
      }
    ]
  }
}

// =============================================================================
// Outputs
// =============================================================================

output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosConnectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
output cosmosPrimaryKey string = cosmosAccount.listKeys().primaryMasterKey
