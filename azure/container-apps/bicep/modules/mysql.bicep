// =============================================================================
// Azure MySQL Flexible Server Module
// =============================================================================
// Deploys MySQL Flexible Server (SERVER ONLY - databases created by services)
// Used by: inventory-service (Python service)
//
// Platform Team Pattern:
// - Infrastructure creates the database SERVER
// - Services create their own DATABASES via migrations in their CI/CD workflows
// - Admin credentials are stored in Key Vault for services to retrieve
// =============================================================================

@description('Environment name (dev, staging, prod) - used for backup/HA settings')
param environment string

@description('Resource location')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('MySQL administrator login')
@secure()
param administratorLogin string

@description('MySQL administrator password')
@secure()
param administratorLoginPassword string

@description('Tags to apply to resources')
param tags object = {}

@description('MySQL SKU name')
param skuName string = 'Standard_B1ms'

@description('MySQL SKU tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

@description('Storage size in GB')
param storageSizeGB int = 20

@description('MySQL version')
@allowed(['5.7', '8.0.21'])
param version string = '8.0.21'

@description('Enable public network access')
param publicNetworkAccess string = 'Enabled'

@description('Key Vault name for storing connection info')
param keyVaultName string = ''

@description('Unique suffix for globally-unique resource names (passed from parent deployment)')
param uniqueSuffix string

// =============================================================================
// Variables
// =============================================================================

var serverName = '${baseName}-${uniqueSuffix}-mysql'

// =============================================================================
// MySQL Flexible Server
// =============================================================================

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = {
  name: serverName
  location: location
  tags: union(tags, {
    component: 'database'
    type: 'mysql'
  })
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: version
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
      autoIoScaling: 'Enabled'
    }
    backup: {
      backupRetentionDays: environment == 'prod' ? 35 : 7
      geoRedundantBackup: environment == 'prod' ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: environment == 'prod' ? 'ZoneRedundant' : 'Disabled'
    }
    network: {
      publicNetworkAccess: publicNetworkAccess
    }
  }
}

// =============================================================================
// Firewall Rules
// =============================================================================

// Allow Azure services
resource allowAzureServicesRule 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-06-30' = {
  name: 'AllowAllWindowsAzureIps'
  parent: mysqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// =============================================================================
// Key Vault Secrets (Admin Credentials & Connection Info)
// =============================================================================
// Services will use these to create their own databases and connection strings

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

// Store admin login
resource adminLoginSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'mysql-admin-login'
  parent: keyVault
  properties: {
    value: administratorLogin
  }
}

// Store admin password
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'mysql-admin-password'
  parent: keyVault
  properties: {
    value: administratorLoginPassword
  }
}

// Store server FQDN for services to build connection strings
resource serverFqdnSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'mysql-server-fqdn'
  parent: keyVault
  properties: {
    value: mysqlServer.properties.fullyQualifiedDomainName
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('MySQL Server name')
output serverName string = mysqlServer.name

@description('MySQL Server FQDN')
output fqdn string = mysqlServer.properties.fullyQualifiedDomainName

@description('MySQL Server resource ID')
output serverId string = mysqlServer.id

@description('Connection string template for services to use (PyMySQL for Python)')
output connectionStringTemplate string = 'mysql+pymysql://{username}:{password}@${mysqlServer.properties.fullyQualifiedDomainName}:3306/{database}'
