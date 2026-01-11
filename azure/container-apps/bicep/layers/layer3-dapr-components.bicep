// ============================================================================
// xshopai Platform - Layer 3: Dapr Components
// Creates: Dapr pub/sub, state store, secret store, config store components
// Depends on: Layer 1 (Core Platform) for Container Apps Environment
// Depends on: Layer 2 (Data Services) for Service Bus, Redis, Key Vault
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Project name prefix for resource naming')
param projectName string = 'xshopai'

@description('Tags to apply to all resources')
param tags object = {
  project: projectName
  environment: environment
  managedBy: 'bicep'
  layer: 'dapr-components'
}

@description('Container Apps Environment Name (from Layer 1)')
param containerAppsEnvName string

@description('Key Vault Name (from Layer 0)')
param keyVaultName string

@description('Managed Identity Client ID (from Layer 0)')
param managedIdentityClientId string

@description('Service Bus Connection String (from Layer 2)')
@secure()
param serviceBusConnectionString string

@description('Redis Host Name (from Layer 2)')
param redisHost string

@description('Redis Primary Key (from Layer 2)')
@secure()
param redisPassword string

// ============================================================================
// Dapr Components
// ============================================================================

module daprComponents '../modules/dapr-components.bicep' = {
  name: 'deploy-dapr-components'
  params: {
    containerAppsEnvName: containerAppsEnvName
    serviceBusConnectionString: serviceBusConnectionString
    redisHost: redisHost
    redisPassword: redisPassword
    keyVaultName: keyVaultName
    managedIdentityClientId: managedIdentityClientId
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Dapr Components deployed successfully')
output daprComponentsDeployed bool = true

@description('Environment tags')
output deploymentTags object = tags
