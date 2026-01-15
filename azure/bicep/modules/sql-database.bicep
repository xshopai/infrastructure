// ============================================================================
// Reusable SQL Database Module
// Version: 1.0.0
// Description: Creates a database on existing Azure SQL Server
// ============================================================================

@description('Name of the database to create')
param databaseName string

@description('Name of the existing SQL Server')
param sqlServerName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Database SKU (Basic, S0, S1, S2, P1, P2, etc.)')
param sku object = {
  name: 'Basic'
  tier: 'Basic'
  capacity: 5
}

@description('Maximum size of the database in bytes')
param maxSizeBytes int = 2147483648 // 2GB

@description('Collation for the database')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Zone redundant')
param zoneRedundant bool = false

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// Reference to existing SQL Server
// ============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' existing = {
  name: sqlServerName
}

// ============================================================================
// SQL Database
// ============================================================================

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  name: databaseName
  parent: sqlServer
  location: location
  tags: tags
  sku: sku
  properties: {
    collation: collation
    maxSizeBytes: maxSizeBytes
    zoneRedundant: zoneRedundant
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Database resource ID')
output databaseId string = sqlDatabase.id

@description('Database name')
output databaseName string = sqlDatabase.name

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('Connection string template (replace {password})')
output connectionStringTemplate string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseName};User ID=${sqlServer.properties.administratorLogin};Password={password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
