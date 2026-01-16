// =================================================================
// Bootstrap Infrastructure Deployment
// =================================================================
// Purpose: Deploy core infrastructure needed to store Bicep modules
// - Azure Container Registry (for Bicep module storage)
// - Resource Group (shared infrastructure)
// - User-Assigned Managed Identity (for GitHub Actions)
// 
// This is deployed ONCE using local module references
// After deployment, all modules are published to ACR
// Future deployments reference modules from ACR
// =================================================================

targetScope = 'subscription'

// =================================================================
// PARAMETERS
// =================================================================

@description('Primary Azure region for all resources')
param location string = 'eastus'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name prefix for all resources')
param projectName string = 'xshopai'

@description('Tags to apply to all resources')
param tags object = {
  Project: 'xshopai'
  ManagedBy: 'Bicep'
  Environment: environment
  Purpose: 'Bootstrap Infrastructure'
}

@description('ACR SKU (Basic, Standard, Premium)')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Standard'

@description('Enable ACR admin user (not recommended for production)')
param acrAdminUserEnabled bool = false

@description('Enable ACR anonymous pull (not recommended for production)')
param acrAnonymousPullEnabled bool = false

// =================================================================
// VARIABLES
// =================================================================

var resourceGroupName = '${projectName}-shared-${environment}-rg'
var acrName = toLower('${projectName}${environment}registry')
var managedIdentityName = '${projectName}-github-${environment}-id'

// =================================================================
// RESOURCE GROUP (using local module reference)
// =================================================================

module resourceGroup '../modules/resource-group.bicep' = {
  name: 'deploy-${resourceGroupName}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// =================================================================
// AZURE CONTAINER REGISTRY (using local module reference)
// =================================================================

module containerRegistry '../modules/container-registry.bicep' = {
  name: 'deploy-${acrName}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: acrName
    location: location
    sku: acrSku
    adminUserEnabled: acrAdminUserEnabled
    anonymousPullEnabled: acrAnonymousPullEnabled
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// =================================================================
// USER-ASSIGNED MANAGED IDENTITY (using local module reference)
// =================================================================
// Used by GitHub Actions to authenticate to Azure
// Assigned AcrPush role on the Container Registry

module managedIdentity '../modules/user-assigned-identity.bicep' = {
  name: 'deploy-${managedIdentityName}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: managedIdentityName
    location: location
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// =================================================================
// ROLE ASSIGNMENTS
// =================================================================
// Grant Managed Identity permissions to push to ACR

module acrPushRoleAssignment '../modules/role-assignment.bicep' = {
  name: 'assign-acr-push-role'
  scope: resourceGroup(resourceGroupName)
  params: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
    principalId: managedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    containerRegistry
    managedIdentity
  ]
}

// =================================================================
// OUTPUTS
// =================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroupName

@description('Container registry name')
output acrName string = acrName

@description('Container registry login server')
output acrLoginServer string = containerRegistry.outputs.loginServer

@description('Managed identity client ID for GitHub Actions')
output managedIdentityClientId string = managedIdentity.outputs.clientId

@description('Managed identity resource ID')
output managedIdentityId string = managedIdentity.outputs.id

@description('Instructions for next steps')
output nextSteps string = '''
Bootstrap deployment complete! Next steps:

1. Configure GitHub Actions federated credentials:
   - Go to Azure Portal → Managed Identity: ${managedIdentityName}
   - Add Federated Credential for GitHub Actions
   - Entity Type: Environment
   - GitHub Organization: <your-org>
   - GitHub Repository: <your-repo>
   - Environment: ${environment}

2. Add GitHub Secrets:
   - AZURE_CLIENT_ID: ${managedIdentity.outputs.clientId}
   - AZURE_TENANT_ID: <your-tenant-id>
   - AZURE_SUBSCRIPTION_ID: <your-subscription-id>

3. Publish Bicep modules to ACR:
   - GitHub Actions workflow will automatically publish modules
   - Modules will be available at: br:${containerRegistry.outputs.loginServer}/bicep/modules/{module-name}:1.0.0

4. Future deployments should reference modules from ACR instead of local paths
'''
