// ============================================================================
// Azure Database for PostgreSQL Flexible Server Module
// ============================================================================
// Deploys PostgreSQL Flexible Server (SERVER ONLY - databases created by services)
// Used by: order-processor-service, audit-service
//
// Platform Team Pattern:
// - Infrastructure creates the database SERVER
// - Services create their own DATABASES via migrations in their CI/CD workflows
// - Admin credentials are stored in Key Vault for services to retrieve
// ============================================================================

@description('Name of the PostgreSQL server')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Administrator login name')
@secure()
param administratorLogin string

@description('Administrator password')
@secure()
param administratorPassword string

@description('PostgreSQL version')
@allowed(['11', '12', '13', '14', '15', '16'])
param version string = '16'

@description('SKU name')
param sku string = 'Standard_B1ms'

@description('Storage size in GB')
@minValue(32)
@maxValue(16384)
param storageSizeGB int = 32

@description('Backup retention days')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Enable high availability')
param enableHighAvailability bool = false

@description('Key Vault name for storing connection info')
param keyVaultName string = ''

// ============================================================================
// Variables
// ============================================================================

var skuTier = startsWith(sku, 'Standard_B') ? 'Burstable' : (startsWith(sku, 'Standard_D') ? 'GeneralPurpose' : 'MemoryOptimized')

// ============================================================================
// Resources
// ============================================================================

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: skuTier
  }
  properties: {
    version: version
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: enableHighAvailability ? 'ZoneRedundant' : 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
}

// Allow Azure services to access
resource firewallRuleAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ============================================================================
// Key Vault Secrets (Admin Credentials & Connection Info)
// ============================================================================
// Services will use these to create their own databases and connection strings

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

// Store admin login
resource adminLoginSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'postgresql-admin-login'
  parent: keyVault
  properties: {
    value: administratorLogin
  }
}

// Store admin password
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'postgresql-admin-password'
  parent: keyVault
  properties: {
    value: administratorPassword
  }
}

// Store server FQDN for services to build connection strings
resource serverFqdnSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'postgresql-server-fqdn'
  parent: keyVault
  properties: {
    value: postgresServer.properties.fullyQualifiedDomainName
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('PostgreSQL Server Resource ID')
output id string = postgresServer.id

@description('PostgreSQL Server Name')
output name string = postgresServer.name

@description('PostgreSQL Server FQDN')
output fqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('PostgreSQL Connection String Template for services to use (replace {database} and {password})')
output connectionStringTemplate string = 'Host=${postgresServer.properties.fullyQualifiedDomainName};Database={database};Username=${administratorLogin};Password={password};SSL Mode=Require;Trust Server Certificate=true'
