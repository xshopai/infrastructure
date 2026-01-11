// =============================================================================
// Azure SQL Server Module
// =============================================================================
// Deploys Azure SQL Server (SERVER ONLY - databases are created by services)
// Used by: order-service, payment-service (.NET services)
// 
// Platform Team Pattern:
// - Infrastructure creates the database SERVER
// - Services create their own DATABASES via migrations in their CI/CD workflows
// - Admin credentials are stored in Key Vault for services to retrieve
// =============================================================================

@description('Resource location')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('SQL Server administrator login')
@secure()
param administratorLogin string

@description('SQL Server administrator password')
@secure()
param administratorLoginPassword string

@description('Tags to apply to resources')
param tags object = {}

@description('Enable public network access')
param publicNetworkAccess string = 'Enabled'

@description('Allowed IP addresses for firewall rules')
param allowedIpAddresses array = []

@description('Allow Azure services to access the server')
param allowAzureServices bool = true

@description('Key Vault name for storing connection info')
param keyVaultName string = ''

@description('Unique suffix for globally-unique resource names (passed from parent deployment)')
param uniqueSuffix string

@description('Azure AD admin object ID for Azure AD-only authentication')
param azureAdAdminObjectId string = ''

@description('Azure AD admin login name')
param azureAdAdminLogin string = ''

@description('Use Azure AD-only authentication (required by MCAPS corporate policy)')
param azureAdOnlyAuthentication bool = true

// =============================================================================
// Variables
// =============================================================================

var serverName = '${baseName}-${uniqueSuffix}-sql'

// =============================================================================
// SQL Server
// =============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: serverName
  location: location
  tags: union(tags, {
    component: 'database'
    type: 'sql-server'
    SecurityControl: azureAdOnlyAuthentication ? 'Compliant' : 'Ignore'
  })
  properties: {
    administratorLogin: azureAdOnlyAuthentication ? null : administratorLogin
    administratorLoginPassword: azureAdOnlyAuthentication ? null : administratorLoginPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: publicNetworkAccess
    administrators: azureAdOnlyAuthentication && !empty(azureAdAdminObjectId) ? {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: azureAdAdminLogin
      sid: azureAdAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    } : null
  }
}

// =============================================================================
// Firewall Rules
// =============================================================================

// Allow Azure services
resource allowAzureServicesRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = if (allowAzureServices) {
  name: 'AllowAllWindowsAzureIps'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Custom IP rules
resource customFirewallRules 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = [for (ip, i) in allowedIpAddresses: {
  name: 'AllowedIP-${i}'
  parent: sqlServer
  properties: {
    startIpAddress: ip
    endIpAddress: ip
  }
}]

// =============================================================================
// Key Vault Secrets (Admin Credentials & Connection Info)
// =============================================================================
// Services will use these to create their own databases and connection strings

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

// Store admin login
resource adminLoginSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'sql-server-admin-login'
  parent: keyVault
  properties: {
    value: administratorLogin
  }
}

// Store admin password
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'sql-server-admin-password'
  parent: keyVault
  properties: {
    value: administratorLoginPassword
  }
}

// Store server FQDN for services to build connection strings
resource serverFqdnSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(keyVaultName)) {
  name: 'sql-server-fqdn'
  parent: keyVault
  properties: {
    value: sqlServer.properties.fullyQualifiedDomainName
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('SQL Server name')
output serverName string = sqlServer.name

@description('SQL Server FQDN')
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Server resource ID')
output serverId string = sqlServer.id

@description('Connection string template for services to use (replace {username}, {database} and {password})')
output connectionStringTemplate string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog={database};Persist Security Info=False;User ID={username};Password={password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
