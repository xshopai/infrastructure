// ============================================================================
// xshopai Platform - Layer 0: Foundation
// Creates: Resource Group, Log Analytics, Managed Identity, Key Vault
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for resources')
param location string

@description('Project name prefix for resource naming')
param projectName string = 'xshopai'

@description('Tags to apply to all resources')
param tags object = {
  project: projectName
  environment: environment
  managedBy: 'bicep'
  layer: 'foundation'
}

// ============================================================================
// Inventory Service Secret Parameters (Service-Prefixed Naming Convention)
// Format: {service-name}-{secret-purpose}
// See: docs/KEY_VAULT_SECRETS.md for complete naming convention
// ============================================================================

@description('MySQL server FQDN for inventory-service')
@secure()
param inventoryServiceMysqlHost string = ''

@description('MySQL server port for inventory-service')
@secure()
param inventoryServiceMysqlPort string = '3306'

@description('MySQL username for inventory-service')
@secure()
param inventoryServiceMysqlUsername string = ''

@description('MySQL password for inventory-service')
@secure()
param inventoryServiceMysqlPassword string = ''

// ============================================================================
// Variables
// ============================================================================

var resourcePrefix = '${projectName}-${environment}'
var resourcePrefixClean = replace(resourcePrefix, '-', '')
// Use environment-based unique suffix for idempotency
var uniqueSuffix = substring(uniqueString(subscription().subscriptionId, projectName, environment), 0, 6)
var resourceGroupName = 'rg-${projectName}-${environment}'

// ============================================================================
// Resource Group
// ============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Log Analytics Workspace
// ============================================================================

module logAnalytics '../modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}-logs'
    location: location
    tags: tags
    retentionInDays: environment == 'prod' ? 90 : 30
  }
}

// ============================================================================
// Managed Identity
// ============================================================================

module managedIdentity '../modules/managed-identity.bicep' = {
  name: 'deploy-managed-identity'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}-identity'
    location: location
    tags: tags
  }
}

// ============================================================================
// Key Vault
// ============================================================================

module keyVault '../modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  scope: resourceGroup
  params: {
    name: '${resourcePrefixClean}${uniqueSuffix}kv'
    location: location
    tags: tags
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    enableSoftDelete: environment == 'prod'
  }
}

// ============================================================================
// Store Log Analytics Credentials in Key Vault
// (Required because GitHub Actions cannot pass secrets between jobs)
// ============================================================================

module logAnalyticsSecret '../modules/key-vault-secret.bicep' = {
  name: 'deploy-log-analytics-secrets'
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    secrets: [
      {
        name: 'log-analytics-customer-id'
        value: logAnalytics.outputs.customerId
      }
      {
        name: 'log-analytics-shared-key'
        value: logAnalytics.outputs.primarySharedKey
      }
    ]
  }
  // dependsOn not needed - Bicep infers from keyVault.outputs.name and logAnalytics.outputs.*
}

// ============================================================================
// Store Inventory Service MySQL Secrets in Key Vault
// Service-Prefixed Naming Convention: {service-name}-{secret-purpose}
// See: docs/KEY_VAULT_SECRETS.md for complete naming convention
// ============================================================================

module inventoryServiceSecrets '../modules/key-vault-secret.bicep' = if (inventoryServiceMysqlHost != '' && inventoryServiceMysqlPassword != '') {
  name: 'deploy-inventory-service-secrets'
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    secrets: [
      {
        name: 'inventory-service-mysql-host'
        value: inventoryServiceMysqlHost
        contentType: 'MySQL Server FQDN for inventory-service'
      }
      {
        name: 'inventory-service-mysql-port'
        value: inventoryServiceMysqlPort
        contentType: 'MySQL Server Port for inventory-service'
      }
      {
        name: 'inventory-service-mysql-username'
        value: inventoryServiceMysqlUsername
        contentType: 'MySQL Username for inventory-service'
      }
      {
        name: 'inventory-service-mysql-password'
        value: inventoryServiceMysqlPassword
        contentType: 'MySQL Password for inventory-service'
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource Group Name')
output resourceGroupName string = resourceGroup.name

@description('Resource Group Location')
output resourceGroupLocation string = resourceGroup.location

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName

@description('Managed Identity Client ID')
output managedIdentityClientId string = managedIdentity.outputs.clientId

@description('Managed Identity Principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Managed Identity Name')
output managedIdentityName string = managedIdentity.outputs.name

@description('Key Vault Name')
output keyVaultName string = keyVault.outputs.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.uri

@description('Unique Suffix for subsequent layers')
output uniqueSuffix string = uniqueSuffix

@description('Resource Prefix for subsequent layers')
output resourcePrefix string = resourcePrefix

@description('Log Analytics Workspace Customer ID')
output logAnalyticsCustomerId string = logAnalytics.outputs.customerId

@description('Log Analytics Workspace Shared Key')
#disable-next-line outputs-should-not-contain-secrets
output logAnalyticsSharedKey string = logAnalytics.outputs.primarySharedKey
