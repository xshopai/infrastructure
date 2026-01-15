// ============================================================================
// Reusable PostgreSQL Database Module
// Version: 1.0.0
// Description: Creates a database on existing PostgreSQL Flexible Server
// ============================================================================

@description('Name of the database to create')
param databaseName string

@description('Name of the existing PostgreSQL Flexible Server')
param postgresServerName string

@description('Character set for the database')
param charset string = 'UTF8'

@description('Collation for the database')
param collation string = 'en_US.utf8'

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// Reference to existing PostgreSQL Server
// ============================================================================

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' existing = {
  name: postgresServerName
}

// ============================================================================
// PostgreSQL Database
// ============================================================================

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = {
  name: databaseName
  parent: postgresServer
  properties: {
    charset: charset
    collation: collation
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Database resource ID')
output databaseId string = postgresDatabase.id

@description('Database name')
output databaseName string = postgresDatabase.name

@description('PostgreSQL Server FQDN')
output postgresServerFqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('PostgreSQL Server name')
output postgresServerName string = postgresServer.name

@description('Connection string template (replace {password})')
output connectionStringTemplate string = 'Host=${postgresServer.properties.fullyQualifiedDomainName};Port=5432;Database=${databaseName};Username=${postgresServer.properties.administratorLogin};Password={password};SslMode=Require;'
