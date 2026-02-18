// MySQL Flexible Server module
// Used by: review-service, admin-service

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Short environment name (dev/pro)')
param shortEnv string

@description('Resource tags')
param tags object

@description('Key Vault name for storing credentials')
param keyVaultName string

@description('Administrator login')
param adminLogin string = 'xshopadmin'

@secure()
@description('Administrator password')
param adminPassword string

// MySQL Flexible Server
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = {
  name: 'mysql-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  sku: {
    name: environment == 'production' ? 'Standard_D2ds_v4' : 'Standard_B1s'
    tier: environment == 'production' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    version: '8.0.21'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: environment == 'production' ? 64 : 20
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: environment == 'production' ? 14 : 7
      geoRedundantBackup: environment == 'production' ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: environment == 'production' ? 'ZoneRedundant' : 'Disabled'
    }
  }
}

// Allow Azure services
resource mysqlFirewall 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-06-30' = {
  parent: mysqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Databases
var databases = [
  'review-db'
  'admin-db'
]

resource mysqlDatabases 'Microsoft.DBforMySQL/flexibleServers/databases@2023-06-30' = [for db in databases: {
  parent: mysqlServer
  name: db
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_unicode_ci'
  }
}]

// Store credentials in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource mysqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-password'
  properties: {
    value: adminPassword
  }
}

resource mysqlConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-connection-string'
  properties: {
    value: 'mysql://${adminLogin}:${adminPassword}@${mysqlServer.properties.fullyQualifiedDomainName}:3306?ssl=true'
  }
}

// Outputs
output mysqlHost string = mysqlServer.properties.fullyQualifiedDomainName
output mysqlServerName string = mysqlServer.name
