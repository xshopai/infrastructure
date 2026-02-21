// PostgreSQL Flexible Server module
// Used by: notification-service

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

// PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: 'psql-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  sku: {
    name: environment == 'production' ? 'Standard_D2s_v3' : 'Standard_B1ms'
    tier: environment == 'production' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    version: '15'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: environment == 'production' ? 64 : 32
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
resource postgresFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Databases
var databases = [
  'notification-db'
]

resource postgresDatabases 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = [for db in databases: {
  parent: postgresServer
  name: db
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}]

// Store credentials in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource postgresPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgres-password'
  properties: {
    value: adminPassword
  }
}

resource postgresConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgres-connection-string'
  properties: {
    value: 'postgresql://${adminLogin}:${adminPassword}@${postgresServer.properties.fullyQualifiedDomainName}:5432/notification-db?sslmode=require'
  }
}

// Outputs
output postgresHost string = postgresServer.properties.fullyQualifiedDomainName
output postgresServerName string = postgresServer.name
