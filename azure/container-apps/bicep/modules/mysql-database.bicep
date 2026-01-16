// ============================================================================
// Azure Database for MySQL Flexible Server Module
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the MySQL Flexible Server')
param name string

@description('Azure region for deployment. Default: Sweden Central')
param location string = 'swedencentral'

@description('Administrator login username')
param administratorLogin string

@description('Administrator login password')
@secure()
param administratorPassword string

@description('MySQL version')
@allowed([
  '5.7'
  '8.0.21'
])
param version string = '8.0.21'

@description('SKU name (e.g., Standard_B1ms, Standard_D2ds_v4)')
param skuName string = 'Standard_B1ms'

@description('Storage size in GB')
@minValue(20)
@maxValue(16384)
param storageSizeGB int = 20

@description('Backup retention days')
@minValue(1)
@maxValue(35)
param backupRetentionDays int = 7

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource mysql 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = {
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
output fqdn string = mysql.properties.fullyQualifiedDomainName

@description('The resource ID of the server')
output resourceId string = mysql.id
