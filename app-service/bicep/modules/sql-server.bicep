// =============================================================================
// SQL Server with databases
// Databases: order_service_db, payment_service_db (Serverless GP Gen5)
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Administrator username')
param adminUser string

@description('Administrator password')
@secure()
param adminPassword string

@description('Resource tags')
param tags object

// =============================================================================
// Variables
// =============================================================================

var sqlServerName = 'sql-${resourcePrefix}'
var databases = [
  'order_service_db'
  'payment_service_db'
]

// =============================================================================
// Resources
// =============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: union(tags, {
    SecurityControl: 'Ignore' // Required for MS internal subscriptions with MCAPS governance
  })
  properties: {
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

// Allow Azure services to connect
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create serverless databases
resource sqlDatabases 'Microsoft.Sql/servers/databases@2023-05-01-preview' = [for db in databases: {
  parent: sqlServer
  name: db
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368 // 32 GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    autoPauseDelay: 60 // Auto-pause after 60 minutes
    minCapacity: 1
    requestedBackupStorageRedundancy: 'Local'
  }
}]

// =============================================================================
// Outputs
// =============================================================================

output sqlServerId string = sqlServer.id
output sqlServerName string = sqlServer.name
output sqlHost string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabases array = databases

// Connection strings for each database
#disable-next-line outputs-should-not-contain-secrets
output orderDbConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=order_service_db;User ID=${adminUser};Password=${adminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
#disable-next-line outputs-should-not-contain-secrets
output paymentDbConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=payment_service_db;User ID=${adminUser};Password=${adminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
