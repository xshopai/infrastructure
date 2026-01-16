// ============================================================================
// Azure Database for PostgreSQL Flexible Server Module
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the PostgreSQL Flexible Server')
param name string

@description('Azure region for deployment. Default: Sweden Central')
param location string = 'swedencentral'

@description('Administrator login username')
param administratorLogin string

@description('Administrator login password')
@secure()
param administratorPassword string

@description('PostgreSQL version')
@allowed([
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
])
param version string = '16'

@description('SKU name (e.g., Standard_B1ms, Standard_D2ds_v4)')
param skuName string = 'Standard_B1ms'

@description('Storage size in GB')
@minValue(32)
@maxValue(16384)
param storageSizeGB int = 32

@description('Backup retention days')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource postgresql 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: name
  location: location
  sku: {
    name: skuName
    tier: contains(skuName, 'B') ? 'Burstable' : 'GeneralPurpose'
  }
  properties: {
    version: version
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
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

@description('The fully qualified domain name of the server')
output fqdn string = postgresql.properties.fullyQualifiedDomainName

@description('The resource ID of the server')
output resourceId string = postgresql.id
