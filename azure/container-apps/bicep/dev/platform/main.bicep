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
// Outputs (for Service Deployments)
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
// Usage Example (for Service Deployments)
// ========================================
/*
// Reference this platform infrastructure from service deployments:

module platformInfra './dev/platform/main.bicep' = {
  name: 'platform-infrastructure'
  scope: subscription()
}

// Then use outputs in your service deployment:
module myService 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/container-app:v1.0.0' = {
  name: 'my-service'
  params: {
    environmentId: platformInfra.outputs.containerAppsEnvironmentId
    managedIdentityId: platformInfra.outputs.managedIdentityId
    ...
  }
}
*/
