// ============================================================================
// Azure SQL Database Module
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the SQL Server')
param serverName string

@description('Name of the SQL Database')
param databaseName string

@description('Azure region for deployment. Default: Sweden Central')
param location string = 'swedencentral'

@description('Administrator login username')
param administratorLogin string

@description('Administrator login password')
@secure()
param administratorPassword string

@description('SKU name for the database')
@allowed([
  'Basic'
  'S0'
  'S1'
  'S2'
  'GP_S_Gen5_1'
  'GP_S_Gen5_2'
])
param skuName string = 'Basic'

@description('Maximum database size in bytes')
param maxSizeBytes int = 2147483648

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: skuName
  }
  properties: {
    maxSizeBytes: maxSizeBytes
  }
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

resource firewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The fully qualified domain name of the SQL Server')
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('The connection string for the database')
output connectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${databaseName};Encrypt=true;'

@description('The resource ID of the database')
output databaseResourceId string = sqlDatabase.id
