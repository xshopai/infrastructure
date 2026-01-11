// ============================================================================
// xshopai Platform - Layer 2: Data Services
// Creates: PostgreSQL, MySQL, SQL Server, Cosmos DB, Redis, Service Bus
// Depends on: Layer 0 (Foundation) - for Key Vault secrets storage
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Project name prefix for resource naming')
param projectName string = 'xshopai'

@description('Tags to apply to all resources')
param tags object = {
  project: projectName
  environment: environment
  managedBy: 'bicep'
  layer: 'data-services'
}

@description('Key Vault Name (from Layer 0)')
param keyVaultName string

@description('Managed Identity Principal ID (from Layer 0)')
param managedIdentityPrincipalId string

@description('Unique suffix for globally-unique resource names (from Layer 0)')
param uniqueSuffix string

// Database Configuration
@description('PostgreSQL administrator login')
@secure()
param postgresAdminLogin string

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

@description('SQL Server administrator login')
@secure()
param sqlServerAdminLogin string

@description('SQL Server administrator password')
@secure()
param sqlServerAdminPassword string

@description('MySQL administrator login')
@secure()
param mysqlAdminLogin string

@description('MySQL administrator password')
@secure()
param mysqlAdminPassword string

// Azure AD Configuration for SQL Server (optional)
@description('Azure AD admin object ID for SQL Server')
param sqlAzureAdAdminObjectId string = ''

@description('Azure AD admin login name for SQL Server')
param sqlAzureAdAdminLogin string = ''

@description('Use Azure AD-only authentication for SQL Server')
param sqlAzureAdOnlyAuthentication bool = false

// ============================================================================
// Variables
// ============================================================================

var resourcePrefix = '${projectName}-${environment}'

// ============================================================================
// Service Bus (for Dapr pub/sub)
// ============================================================================

module serviceBus '../modules/service-bus.bicep' = {
  name: 'deploy-service-bus'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-servicebus'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Standard' : 'Basic'
    managedIdentityPrincipalId: managedIdentityPrincipalId
  }
}

// ============================================================================
// Redis Cache (for Dapr state store and caching)
// ============================================================================

module redis '../modules/redis.bicep' = {
  name: 'deploy-redis'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-redis'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Standard' : 'Basic'
    capacity: environment == 'prod' ? 1 : 0
  }
}

// ============================================================================
// Cosmos DB (MongoDB API)
// ============================================================================

module cosmosDb '../modules/cosmos-db.bicep' = {
  name: 'deploy-cosmos-db'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-cosmos'
    location: location
    tags: tags
    enableFreeTier: false
    enableServerless: environment == 'dev'
    keyVaultName: keyVaultName
  }
}

// ============================================================================
// PostgreSQL Flexible Server
// ============================================================================

module postgresql '../modules/postgresql.bicep' = {
  name: 'deploy-postgresql'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-psql'
    location: location
    tags: tags
    administratorLogin: postgresAdminLogin
    administratorPassword: postgresAdminPassword
    sku: environment == 'prod' ? 'Standard_D2s_v3' : 'Standard_B1ms'
    storageSizeGB: environment == 'prod' ? 128 : 32
    keyVaultName: keyVaultName
  }
}

// ============================================================================
// Azure SQL Server
// ============================================================================

module sqlServer '../modules/sql-server.bicep' = {
  name: 'deploy-sql-server'
  params: {
    location: location
    baseName: resourcePrefix
    uniqueSuffix: uniqueSuffix
    tags: tags
    administratorLogin: sqlServerAdminLogin
    administratorLoginPassword: sqlServerAdminPassword
    keyVaultName: keyVaultName
    azureAdAdminObjectId: sqlAzureAdAdminObjectId
    azureAdAdminLogin: sqlAzureAdAdminLogin
    azureAdOnlyAuthentication: sqlAzureAdOnlyAuthentication
  }
}

// ============================================================================
// MySQL Flexible Server
// ============================================================================

module mysql '../modules/mysql.bicep' = {
  name: 'deploy-mysql'
  params: {
    environment: environment
    location: location
    baseName: resourcePrefix
    uniqueSuffix: uniqueSuffix
    tags: tags
    administratorLogin: mysqlAdminLogin
    administratorLoginPassword: mysqlAdminPassword
    skuName: environment == 'prod' ? 'Standard_D2ds_v4' : 'Standard_B1ms'
    skuTier: environment == 'prod' ? 'GeneralPurpose' : 'Burstable'
    keyVaultName: keyVaultName
  }
}

// ============================================================================
// Store connection strings in Key Vault
// ============================================================================

module secrets '../modules/key-vault-secrets.bicep' = {
  name: 'deploy-data-secrets'
  params: {
    keyVaultName: keyVaultName
    secrets: [
      { name: 'service-bus-connection-string', value: serviceBus.outputs.connectionString }
      { name: 'redis-connection-string', value: redis.outputs.connectionString }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Service Bus Namespace')
output serviceBusNamespace string = serviceBus.outputs.namespaceName

@description('Service Bus Connection String')
output serviceBusConnectionString string = serviceBus.outputs.connectionString

@description('Redis Host Name')
output redisHostName string = redis.outputs.hostName

@description('Redis Primary Key')
output redisPrimaryKey string = redis.outputs.primaryKey

@description('Redis Connection String')
output redisConnectionString string = redis.outputs.connectionString

@description('Cosmos DB Account Name')
output cosmosDbAccountName string = cosmosDb.outputs.accountName

@description('Cosmos DB Endpoint')
output cosmosDbEndpoint string = cosmosDb.outputs.endpoint

@description('PostgreSQL Server FQDN')
output postgresqlFqdn string = postgresql.outputs.fqdn

@description('PostgreSQL Server Name')
output postgresqlServerName string = postgresql.outputs.serverName

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.outputs.serverFqdn

@description('SQL Server Name')
output sqlServerName string = sqlServer.outputs.serverName

@description('MySQL Server FQDN')
output mysqlFqdn string = mysql.outputs.fqdn

@description('MySQL Server Name')
output mysqlServerName string = mysql.outputs.serverName
