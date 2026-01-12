// ============================================================================
// xshopai Platform - Azure Container Apps Infrastructure
// Main deployment orchestrator
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
}

// Dapr is always enabled via Container Apps Environment configuration

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

// Azure AD Configuration for SQL Server (required for MCAPS compliance)
@description('Azure AD admin object ID for SQL Server (required for MCAPS corporate policy)')
param sqlAzureAdAdminObjectId string = ''

@description('Azure AD admin login name for SQL Server')
param sqlAzureAdAdminLogin string = ''

@description('Use Azure AD-only authentication for SQL Server (set true for MCAPS compliance in prod)')
param sqlAzureAdOnlyAuthentication bool = false

@description('Unique suffix for globally-unique resource names (passed from subscription-level deployment, or auto-generated for standalone deployments)')
param uniqueSuffix string = substring(uniqueString(subscription().subscriptionId, environment), 0, 6)

// ============================================================================
// Variables
// ============================================================================

var resourcePrefix = '${projectName}-${environment}'
var resourcePrefixClean = replace(resourcePrefix, '-', '')
// uniqueSuffix is now passed as a parameter from deploy.bicep for consistency

// ============================================================================
// Core Infrastructure Modules
// ============================================================================

// Log Analytics Workspace (required for Container Apps)
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    name: '${resourcePrefix}-logs'
    location: location
    tags: tags
    retentionInDays: environment == 'prod' ? 90 : 30
  }
}

// Managed Identity for services
module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'deploy-managed-identity'
  params: {
    name: '${resourcePrefix}-identity'
    location: location
    tags: tags
  }
}

// Key Vault for secrets (globally unique name required)
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    name: '${resourcePrefixClean}${uniqueSuffix}kv'
    location: location
    tags: tags
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    enableSoftDelete: environment == 'prod'
  }
}

// Container Registry (globally unique name required)
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'deploy-container-registry'
  params: {
    name: '${resourcePrefixClean}${uniqueSuffix}acr'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Premium' : 'Basic'
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
  }
}

// ============================================================================
// Data Services
// ============================================================================

// Azure Service Bus (for Dapr pub/sub - globally unique namespace required)
module serviceBus 'modules/service-bus.bicep' = {
  name: 'deploy-service-bus'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-servicebus'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Standard' : 'Basic'
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
  }
}

// Azure Cache for Redis (for Dapr state store and caching - globally unique DNS required)
module redis 'modules/redis.bicep' = {
  name: 'deploy-redis'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-redis'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Standard' : 'Basic'
    capacity: environment == 'prod' ? 1 : 0
  }
}

// Cosmos DB (MongoDB API) for user-service, product-service, etc.
// Note: Only creates account. Services create their own databases/collections.
// Note: Free tier not available on internal/MCAPS subscriptions, use serverless instead
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: 'deploy-cosmos-db'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-cosmos'
    location: location
    tags: tags
    enableFreeTier: false
    enableServerless: environment == 'dev'
    keyVaultName: keyVault.outputs.name
  }
}

// PostgreSQL Flexible Server (for order-processor-service, audit-service)
// Note: Only creates server. Services create their own databases.
module postgresql 'modules/postgresql.bicep' = {
  name: 'deploy-postgresql'
  params: {
    name: '${resourcePrefix}-${uniqueSuffix}-psql'
    location: location
    tags: tags
    administratorLogin: postgresAdminLogin
    administratorPassword: postgresAdminPassword
    sku: environment == 'prod' ? 'Standard_D2s_v3' : 'Standard_B1ms'
    storageSizeGB: environment == 'prod' ? 128 : 32
    keyVaultName: keyVault.outputs.name
  }
}

// Azure SQL Server (for order-service, payment-service - .NET services)
// Note: Only creates server. Services create their own databases.
// Note: MCAPS corporate policy requires Azure AD-only authentication
module sqlServer 'modules/sql-server.bicep' = {
  name: 'deploy-sql-server'
  params: {
    location: location
    baseName: resourcePrefix
    uniqueSuffix: uniqueSuffix
    tags: tags
    administratorLogin: sqlServerAdminLogin
    administratorLoginPassword: sqlServerAdminPassword
    keyVaultName: keyVault.outputs.name
    azureAdAdminObjectId: sqlAzureAdAdminObjectId
    azureAdAdminLogin: sqlAzureAdAdminLogin
    azureAdOnlyAuthentication: sqlAzureAdOnlyAuthentication
  }
}

// Azure MySQL Flexible Server (for inventory-service - Python service)
// Note: Only creates server. Services create their own databases.
module mysql 'modules/mysql.bicep' = {
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
    keyVaultName: keyVault.outputs.name
  }
}

// ============================================================================
// Container Apps Environment
// ============================================================================

module containerAppsEnv 'modules/container-apps-env.bicep' = {
  name: 'deploy-container-apps-env'
  params: {
    name: '${resourcePrefix}-cae'
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalytics.outputs.primarySharedKey
  }
}

// ============================================================================
// Dapr Components
// ============================================================================

module daprComponents 'modules/dapr-components.bicep' = {
  name: 'deploy-dapr-components'
  params: {
    containerAppsEnvName: containerAppsEnv.outputs.name
    serviceBusConnectionString: serviceBus.outputs.connectionString
    redisHost: redis.outputs.hostName
    redisPassword: redis.outputs.primaryKey
    keyVaultName: keyVault.outputs.name
    managedIdentityClientId: managedIdentity.outputs.clientId
  }
}

// ============================================================================
// Store secrets in Key Vault
// Note: Database credentials are stored by their respective modules
// ============================================================================

module secrets 'modules/key-vault-secrets.bicep' = {
  name: 'deploy-secrets'
  params: {
    keyVaultName: keyVault.outputs.name
    secrets: [
      { name: 'service-bus-connection-string', value: serviceBus.outputs.connectionString }
      { name: 'redis-connection-string', value: redis.outputs.connectionString }
      { name: 'acr-login-server', value: containerRegistry.outputs.loginServer }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Container Apps Environment ID')
output containerAppsEnvId string = containerAppsEnv.outputs.id

@description('Container Apps Environment Name')
output containerAppsEnvName string = containerAppsEnv.outputs.name

@description('Container Apps Environment Default Domain')
output containerAppsEnvDomain string = containerAppsEnv.outputs.defaultDomain

@description('Container Registry Login Server')
output acrLoginServer string = containerRegistry.outputs.loginServer

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.uri

@description('Managed Identity Client ID')
output managedIdentityClientId string = managedIdentity.outputs.clientId

@description('Managed Identity Principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Service Bus Namespace')
output serviceBusNamespace string = serviceBus.outputs.namespaceName

@description('Redis Host Name')
output redisHostName string = redis.outputs.hostName

@description('Cosmos DB Account Name')
output cosmosDbAccountName string = cosmosDb.outputs.accountName

@description('PostgreSQL Server FQDN')
output postgresqlFqdn string = postgresql.outputs.fqdn

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.outputs.serverFqdn

@description('MySQL Server FQDN')
output mysqlFqdn string = mysql.outputs.fqdn
