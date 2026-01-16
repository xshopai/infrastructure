// ========================================
// Platform Infrastructure - Development Environment
// ========================================
// Purpose: Deploy shared platform infrastructure for Container Apps in dev environment
// Dependencies: Bootstrap infrastructure (ACR must exist)
// Phase: Phase 2 - Platform Infrastructure
// ========================================

targetScope = 'subscription'

// ========================================
// Parameters
// ========================================

@description('Azure region for all resources')
param location string = 'eastus'

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Common tags for all resources')
param tags object = {
  Environment: environment
  Project: 'xshopai'
  ManagedBy: 'Bicep'
  CostCenter: 'Engineering'
}

@description('Log Analytics workspace retention in days')
param logAnalyticsRetentionDays int = 30

@description('PostgreSQL administrator username')
param postgresAdminUsername string = 'xshopadmin'

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

@description('PostgreSQL version')
param postgresVersion string = '16'

// ========================================
// Redis Configuration
// ========================================

@description('Redis SKU (Basic, Standard, Premium)')
param redisSku string = 'Basic'

@description('Redis SKU family (C for Basic/Standard, P for Premium)')
param redisFamily string = 'C'

@description('Redis capacity (0-6 for Basic/Standard, 1-5 for Premium)')
param redisCapacity int = 0

// ========================================
// Service Bus Configuration
// ========================================

@description('Service Bus SKU (Basic, Standard, Premium)')
param serviceBusSku string = 'Standard'

// ========================================
// SQL Server Configuration
// ========================================

@description('SQL Server administrator username')
param sqlAdminUsername string = 'sqladmin'

@description('SQL Server administrator password')
@secure()
param sqlAdminPassword string

@description('SQL Server version')
param sqlVersion string = '12.0'

// ========================================
// MySQL Configuration
// ========================================

@description('MySQL administrator username')
param mysqlAdminUsername string = 'mysqladmin'

@description('MySQL administrator password')
@secure()
param mysqlAdminPassword string

@description('MySQL version')
param mysqlVersion string = '8.0'

// ========================================
// Module: Resource Group
// ========================================

module rg 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/resource-group:v1.0.0' = {
  name: 'rg-xshopai-${environment}'
  scope: subscription()
  params: {
    name: 'rg-xshopai-${environment}'
    location: location
    tags: tags
  }
}

// ========================================
// Module: Log Analytics Workspace
// ========================================

module logAnalytics 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/log-analytics:v1.0.0' = {
  name: 'log-xshopai-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'log-xshopai-${environment}'
    location: location
    retentionInDays: logAnalyticsRetentionDays
    tags: tags
  }
}

// ========================================
// Module: Container Apps Environment
// ========================================

module containerEnv 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/container-apps-environment:v1.0.0' = {
  name: 'cae-xshopai-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'cae-xshopai-${environment}'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    internalOnly: false
    zoneRedundant: false
    tags: tags
  }
}

// ========================================
// Module: Managed Identity (for Container Apps)
// ========================================

module managedIdentity 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/managed-identity:v1.0.0' = {
  name: 'id-xshopai-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'id-xshopai-${environment}'
    location: location
    tags: tags
  }
}

// ========================================
// Module: Key Vault
// ========================================

module keyVault 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/key-vault:v1.0.0' = {
  name: 'kv-xshopai-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'kv-xshopai-${environment}'
    location: location
    sku: 'standard'
    enableRbacAuthorization: true
    tags: tags
  }
}

// ========================================
// RBAC: Grant Managed Identity Access to Key Vault Secrets
// ========================================
// Allows Container Apps (using Managed Identity) to read secrets from Key Vault
// Built-in Role: "Key Vault Secrets User" (read-only access to secret contents)
// ========================================
// NOTE: Role assignments must be deployed using a module at subscription scope

module keyVaultRoleAssignment 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/key-vault-role-assignment:v1.0.0' = {
  name: 'kv-role-assignment-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
  }
  dependsOn: [
    keyVault
    managedIdentity
  ]
}

// ========================================
// Database Infrastructure
// ========================================

// PostgreSQL for product-service
module postgresProduct 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/postgresql-database:v1.0.0' = {
  name: 'psql-product-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'psql-xshopai-product-${environment}'
    location: location
    administratorLogin: postgresAdminUsername
    administratorPassword: postgresAdminPassword
    version: postgresVersion
    skuName: 'Standard_B1ms'
    storageSizeGB: 32
    backupRetentionDays: 7
    tags: tags
  }
}

// PostgreSQL for user-service
module postgresUser 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/postgresql-database:v1.0.0' = {
  name: 'psql-user-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'psql-xshopai-user-${environment}'
    location: location
    administratorLogin: postgresAdminUsername
    administratorPassword: postgresAdminPassword
    version: postgresVersion
    skuName: 'Standard_B1ms'
    storageSizeGB: 32
    backupRetentionDays: 7
    tags: tags
  }
}

// PostgreSQL for order-service
module postgresOrder 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/postgresql-database:v1.0.0' = {
  name: 'psql-order-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'psql-xshopai-order-${environment}'
    location: location
    administratorLogin: postgresAdminUsername
    administratorPassword: postgresAdminPassword
    version: postgresVersion
    skuName: 'Standard_B1ms'
    storageSizeGB: 32
    backupRetentionDays: 7
    tags: tags
  }
}

// MongoDB (Cosmos DB) for shared services
module cosmosShared 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/cosmos-database:v1.0.0' = {
  name: 'cosmos-shared-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'cosmos-xshopai-${environment}'
    location: location
    apiType: 'MongoDB'
    serverless: true
    tags: tags
  }
}

// ========================================
// Azure Cache for Redis (Caching, Session Management)
// ========================================

module redis 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/redis:v1.0.0' = {
  name: 'redis-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'redis-xshopai-${environment}'
    location: location
    sku: redisSku
    capacity: redisCapacity
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    tags: tags
  }
}

// ========================================
// Azure Service Bus (Messaging Backbone)
// ========================================

module serviceBus 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/service-bus:v1.0.0' = {
  name: 'sb-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'sb-xshopai-${environment}'
    location: location
    sku: serviceBusSku
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    tags: tags
  }
}

// ========================================
// Azure SQL Database (for .NET services)
// ========================================

// SQL Server for order-service and payment-service
module sqlServer 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/sql-server:v1.0.0' = {
  name: 'sql-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    baseName: 'sql-xshopai'
    uniqueSuffix: environment
    location: location
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    keyVaultName: keyVault.outputs.name
    tags: tags
  }
}

// ========================================
// Azure Database for MySQL (if needed)
// ========================================

// MySQL Flexible Server for cart-service
module mysqlCart 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/mysql-database:v1.0.0' = {
  name: 'mysql-cart-${environment}'
  scope: resourceGroup('rg-xshopai-${environment}')
  params: {
    name: 'mysql-xshopai-cart-${environment}'
    location: location
    administratorLogin: mysqlAdminUsername
    administratorPassword: mysqlAdminPassword
    version: mysqlVersion
    skuName: 'Standard_B1ms'
    storageSizeGB: 32
    backupRetentionDays: 7
    tags: tags
  }
}

// ========================================// Outputs (for Service Deployments)
// ========================================

@description('Resource Group name')
output resourceGroupName string = rg.outputs.name

@description('Container Apps Environment ID')
output containerAppsEnvironmentId string = containerEnv.outputs.resourceId

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerEnv.outputs.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName

@description('Managed Identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Managed Identity ID')
output managedIdentityId string = managedIdentity.outputs.id

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.uri

// ========================================
// Database Outputs
// ========================================

@description('PostgreSQL Product Server FQDN')
output postgresProductFqdn string = postgresProduct.outputs.fqdn

@description('PostgreSQL User Server FQDN')
output postgresUserFqdn string = postgresUser.outputs.fqdn

@description('PostgreSQL Order Server FQDN')
output postgresOrderFqdn string = postgresOrder.outputs.fqdn

@description('Cosmos DB Connection String')
@secure()
output cosmosConnectionString string = cosmosShared.outputs.connectionString

@description('Cosmos DB Resource ID')
output cosmosResourceId string = cosmosShared.outputs.resourceId

@description('Redis Cache Hostname')
output redisHostname string = redis.outputs.hostName

@description('Redis Cache Port')
output redisPort int = redis.outputs.sslPort

@description('Redis Primary Key')
@secure()
output redisPrimaryKey string = redis.outputs.primaryKey

@description('Service Bus Namespace Name')
output serviceBusNamespace string = serviceBus.outputs.namespaceName

@description('Service Bus Primary Connection String')
@secure()
output serviceBusConnectionString string = serviceBus.outputs.connectionString

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.outputs.serverFqdn

@description('SQL Server Name')
output sqlServerName string = sqlServer.outputs.serverName

@description('MySQL Cart Server FQDN')
output mysqlCartFqdn string = mysqlCart.outputs.fqdn
