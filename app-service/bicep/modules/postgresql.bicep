// =============================================================================
// PostgreSQL Flexible Server v15 with databases
// Databases: audit_service_db, order_processor_db
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

@description('PostgreSQL server version')
@allowed(['11', '12', '13', '14', '15', '16'])
param serverVersion string = '15'

@description('Compute SKU')
param skuName string = 'Standard_B1ms'

@description('Compute tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

@description('Storage size in GB')
param storageSizeGB int = 32

// =============================================================================
// Variables
// =============================================================================

var postgresServerName = 'psql-${resourcePrefix}'
var databases = [
  'audit_service_db'
  'order_processor_db'
]

// =============================================================================
// Resources
// =============================================================================

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    version: serverVersion
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

// Allow Azure services to connect
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create databases
resource postgresDbResources 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = [for db in databases: {
  parent: postgresServer
  name: db
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}]

// =============================================================================
// Outputs
// =============================================================================

output postgresServerId string = postgresServer.id
output postgresServerName string = postgresServer.name
output postgresHost string = postgresServer.properties.fullyQualifiedDomainName
output postgresDatabases array = databases
