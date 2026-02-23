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

// =============================================================================
// SKU Configuration - Production Level
// =============================================================================
// Using GeneralPurpose tier for all environments (no auto-pause, production-grade)
// D2ds_v4: 2 vCores, 8 GB RAM - suitable for production workloads

var skuConfig = {
  name: 'Standard_D2ds_v4'
  tier: 'GeneralPurpose'
  storageSizeGB: 128
}

@description('Availability zone for the server (prevents auto-pause)')
param availabilityZone string = '1'

// =============================================================================
// Variables
// =============================================================================

var postgresServerName = 'psql-${resourcePrefix}'
var databases = [
  'audit_service_db'
  'order_processor_db'
]

// =============================================================================
// IMPORTANT: Auto-Pause Behavior
// =============================================================================
// Burstable tier (B-series) has auto-pause enabled by default to save costs.
// Server pauses after 1 hour of inactivity and resumes on next connection.
// 
// To DISABLE auto-pause, you have two options:
// 1. Set availabilityZone (deployed to specific zone, prevents auto-pause)
// 2. Upgrade to GeneralPurpose tier (significantly more expensive)
//
// Current config: Using availabilityZone='1' to prevent auto-pause while
// keeping cost-effective Burstable tier.
// =============================================================================

// =============================================================================
// Resources
// =============================================================================

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: skuConfig.name
    tier: skuConfig.tier
  }
  properties: {
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    version: serverVersion
    storage: {
      storageSizeGB: skuConfig.storageSizeGB
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    availabilityZone: availabilityZone
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
