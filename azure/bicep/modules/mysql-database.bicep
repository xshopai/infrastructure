// ============================================================================
// Reusable MySQL Database Module
// Version: 1.0.0
// Description: Creates a database on existing MySQL Flexible Server
// ============================================================================

@description('Name of the database to create')
param databaseName string

@description('Name of the existing MySQL Flexible Server')
param mysqlServerName string

@description('Character set for the database')
param charset string = 'utf8mb4'

@description('Collation for the database')
param collation string = 'utf8mb4_unicode_ci'

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// Reference to existing MySQL Server
// ============================================================================

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' existing = {
  name: mysqlServerName
}

// ============================================================================
// MySQL Database
// ============================================================================

resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2023-06-30' = {
  name: databaseName
  parent: mysqlServer
  properties: {
    charset: charset
    collation: collation
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Database resource ID')
output databaseId string = mysqlDatabase.id

@description('Database name')
output databaseName string = mysqlDatabase.name

@description('MySQL Server FQDN')
output mysqlServerFqdn string = mysqlServer.properties.fullyQualifiedDomainName

@description('MySQL Server name')
output mysqlServerName string = mysqlServer.name

@description('Connection string template (replace {password})')
output connectionStringTemplate string = 'Server=${mysqlServer.properties.fullyQualifiedDomainName};Port=3306;Database=${databaseName};Uid=${mysqlServer.properties.administratorLogin};Pwd={password};SslMode=Required;'
