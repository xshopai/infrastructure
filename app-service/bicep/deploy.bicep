// =============================================================================
// xShopAI - Subscription-level Deployment
// =============================================================================
// Creates resource group and deploys all infrastructure
// Deploy with: az deployment sub create --location <region> --template-file deploy.bicep --parameters parameters.dev.json
//
// This is the ENTRY POINT for Bicep deployments - it creates the resource group
// and then deploys main.bicep as a module into it.
// =============================================================================

targetScope = 'subscription'

// =============================================================================
// Parameters
// =============================================================================

@description('Environment name (dev, prod)')
@allowed(['dev', 'prod'])
param environment string

@description('Resource suffix (e.g., as01, bicep)')
param suffix string

@description('Azure region for resource deployment')
param location string

// Database admin usernames
param postgresAdminUser string = 'pgadmin'
param mysqlAdminUser string = 'mysqladmin'
param sqlAdminUser string = 'sqladmin'
param rabbitmqUser string = 'admin'

// Database admin passwords
@secure()
param postgresAdminPassword string

@secure()
param mysqlAdminPassword string

@secure()
param sqlAdminPassword string

@secure()
param rabbitmqPassword string

// JWT configuration
@secure()
param jwtSecret string
param jwtAlgorithm string = 'HS256'
param jwtIssuer string = 'auth-service'
param jwtAudience string = 'xshopai-platform'
param jwtExpiresIn string = '24h'

// Service tokens
@secure()
param adminServiceToken string
@secure()
param authServiceToken string
@secure()
param userServiceToken string
@secure()
param cartServiceToken string
@secure()
param orderServiceToken string
@secure()
param productServiceToken string
@secure()
param webBffToken string

@description('Azure AD Object ID of user/service principal to grant Key Vault access (optional)')
param keyVaultAdminObjectId string = ''

@description('Principal ID of GitHub Actions OIDC service principal (for Playwright storage role assignment)')
param githubActionsPrincipalId string = ''

// =============================================================================
// Variables
// =============================================================================

var resourceGroupName = 'rg-xshopai-${suffix}'
var tags = {
  project: 'xshopai'
  environment: environment
  suffix: suffix
  managedBy: 'bicep'
}

// =============================================================================
// Resource Group
// =============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// =============================================================================
// Infrastructure Deployment (into Resource Group)
// =============================================================================

module infrastructure 'main.bicep' = {
  name: 'infrastructure-${uniqueString(deployment().name)}'
  scope: resourceGroup
  params: {
    environment: environment
    suffix: suffix
    location: location
    postgresAdminUser: postgresAdminUser
    postgresAdminPassword: postgresAdminPassword
    mysqlAdminUser: mysqlAdminUser
    mysqlAdminPassword: mysqlAdminPassword
    sqlAdminUser: sqlAdminUser
    sqlAdminPassword: sqlAdminPassword
    rabbitmqUser: rabbitmqUser
    rabbitmqPassword: rabbitmqPassword
    jwtSecret: jwtSecret
    jwtAlgorithm: jwtAlgorithm
    jwtIssuer: jwtIssuer
    jwtAudience: jwtAudience
    jwtExpiresIn: jwtExpiresIn
    adminServiceToken: adminServiceToken
    authServiceToken: authServiceToken
    userServiceToken: userServiceToken
    cartServiceToken: cartServiceToken
    orderServiceToken: orderServiceToken
    productServiceToken: productServiceToken
    webBffToken: webBffToken
    keyVaultAdminObjectId: keyVaultAdminObjectId
    githubActionsPrincipalId: githubActionsPrincipalId
  }
}

// =============================================================================
// Outputs
// =============================================================================

output resourceGroupName string = resourceGroup.name
output resourceGroupId string = resourceGroup.id
output location string = resourceGroup.location

// Pass through outputs from infrastructure module
output logAnalyticsWorkspaceId string = infrastructure.outputs.logAnalyticsWorkspaceId
output appInsightsName string = infrastructure.outputs.appInsightsName
output appServicePlanName string = infrastructure.outputs.appServicePlanName
output keyVaultName string = infrastructure.outputs.keyVaultName
