// =============================================================================
// MySQL Flexible Server 8.0 with database
// Database: inventory_service_db
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

@description('MySQL server version')
@allowed(['5.7', '8.0.21'])
param serverVersion string = '8.0.21'

@description('Compute SKU - Production Level')
param skuName string = 'Standard_D2ds_v4'

@description('Compute tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'GeneralPurpose'

@description('Storage size in GB')
param storageSizeGB int = 128

// =============================================================================
// Variables
// =============================================================================

var mysqlServerName = 'mysql-${resourcePrefix}'
var databaseName = 'inventory_service_db'

// =============================================================================
// Resources
// =============================================================================

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = {
  name: mysqlServerName
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
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Allow Azure services to connect
resource allowAzureServices 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-06-30' = {
  parent: mysqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create database
resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2023-06-30' = {
  parent: mysqlServer
  name: databaseName
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_general_ci'
  }
}

// =============================================================================
// Outputs
// =============================================================================

output mysqlServerId string = mysqlServer.id
output mysqlServerName string = mysqlServer.name
output mysqlHost string = mysqlServer.properties.fullyQualifiedDomainName
output mysqlDatabaseName string = databaseName
// SQLAlchemy URL format for Flask/Python apps (mysql+pymysql://user:pass@host/db?ssl_mode=REQUIRED)
#disable-next-line outputs-should-not-contain-secrets
output mysqlConnectionString string = 'mysql+pymysql://${adminUser}:${adminPassword}@${mysqlServer.properties.fullyQualifiedDomainName}/${databaseName}?ssl_mode=REQUIRED'
