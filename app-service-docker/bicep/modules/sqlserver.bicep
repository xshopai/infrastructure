// SQL Server module
// Used by: order-service, payment-service, cart-service

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

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: 'sql-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Allow Azure services
resource sqlFirewall 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Databases
var databases = [
  { name: 'cart-db', sku: environment == 'production' ? 'S1' : 'Basic', tier: environment == 'production' ? 'Standard' : 'Basic' }
  { name: 'order-db', sku: environment == 'production' ? 'S1' : 'Basic', tier: environment == 'production' ? 'Standard' : 'Basic' }
  { name: 'payment-db', sku: environment == 'production' ? 'S1' : 'Basic', tier: environment == 'production' ? 'Standard' : 'Basic' }
]

resource sqlDatabases 'Microsoft.Sql/servers/databases@2023-05-01-preview' = [for db in databases: {
  parent: sqlServer
  name: db.name
  location: location
  sku: {
    name: db.sku
    tier: db.tier
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2GB
  }
}]

// Store credentials in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sqlserver-password'
  properties: {
    value: adminPassword
  }
}

resource sqlConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sqlserver-connection-string'
  properties: {
    value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;User ID=${adminLogin};Password=${adminPassword};Encrypt=True;TrustServerCertificate=False;'
  }
}

// Outputs
output sqlServerHost string = sqlServer.properties.fullyQualifiedDomainName
output sqlServerName string = sqlServer.name
