// ============================================================================
// xshopai Platform - Layer 1: Core Platform
// Creates: Container Apps Environment, Container Registry
// Depends on: Layer 0 (Foundation)
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
  layer: 'core-platform'
}

@description('Log Analytics Workspace ID (from Layer 0)')
param logAnalyticsWorkspaceId string

@description('Managed Identity Principal ID (from Layer 0)')
param managedIdentityPrincipalId string

@description('Unique suffix for globally-unique resource names (from Layer 0)')
param uniqueSuffix string

// ============================================================================
// Variables
// ============================================================================

var resourcePrefix = '${projectName}-${environment}'
var resourcePrefixClean = replace(resourcePrefix, '-', '')

// ============================================================================
// Container Apps Environment
// ============================================================================

module containerAppsEnv '../modules/container-apps-env.bicep' = {
  name: 'deploy-container-apps-env'
  params: {
    name: '${resourcePrefix}-cae'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

// ============================================================================
// Container Registry
// ============================================================================

module containerRegistry '../modules/container-registry.bicep' = {
  name: 'deploy-container-registry'
  params: {
    name: '${resourcePrefixClean}${uniqueSuffix}acr'
    location: location
    tags: tags
    sku: environment == 'prod' ? 'Premium' : 'Basic'
    managedIdentityPrincipalId: managedIdentityPrincipalId
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

@description('Container Registry Name')
output containerRegistryName string = containerRegistry.outputs.name

@description('Container Registry Login Server')
output acrLoginServer string = containerRegistry.outputs.loginServer
