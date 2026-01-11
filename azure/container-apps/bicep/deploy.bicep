// ============================================================================
// xshopai Platform - Subscription-Level Deployment
// Creates resource group and deploys all infrastructure
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for resources')
param location string = 'uksouth'

@description('Project name prefix for resource naming')
param projectName string = 'xshopai'

@description('Tags to apply to all resources')
param tags object = {
  project: projectName
  environment: environment
  managedBy: 'bicep'
  createdDate: utcNow('yyyy-MM-dd')
}

// Service Configuration
@description('Container image tag to deploy')
param imageTag string = 'latest'

@description('Enable Dapr for services')
param daprEnabled bool = true

// Scaling Configuration
@description('Minimum replicas for services')
param minReplicas int = environment == 'prod' ? 2 : 1

@description('Maximum replicas for services')
param maxReplicas int = environment == 'prod' ? 10 : 3

// Database Configuration
@description('PostgreSQL administrator login')
@secure()
param postgresAdminLogin string = 'pgadmin'

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

@description('SQL Server administrator login')
@secure()
param sqlServerAdminLogin string = 'sqladmin'

@description('SQL Server administrator password')
@secure()
param sqlServerAdminPassword string

@description('MySQL administrator login')
@secure()
param mysqlAdminLogin string = 'mysqladmin'

@description('MySQL administrator password')
@secure()
param mysqlAdminPassword string

// Azure AD Configuration for SQL Server (optional, for enhanced security)
@description('Azure AD admin object ID for SQL Server (required only if using Azure AD auth)')
param sqlAzureAdAdminObjectId string = ''

@description('Azure AD admin login name for SQL Server')
param sqlAzureAdAdminLogin string = ''

@description('Use Azure AD-only authentication for SQL Server (set to true for MCAPS compliance in prod)')
param sqlAzureAdOnlyAuthentication bool = false

@description('Unique deployment suffix (leave empty for auto-generated, or provide custom value)')
param deploymentSuffix string = ''

// ============================================================================
// Variables
// ============================================================================

// Generate a unique suffix if not provided (first 6 chars of subscription hash)
var uniqueSuffix = empty(deploymentSuffix) ? substring(uniqueString(subscription().subscriptionId, environment), 0, 6) : deploymentSuffix
var resourceGroupName = 'rg-${projectName}-${environment}-${uniqueSuffix}'

// ============================================================================
// Resource Group
// ============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Infrastructure Deployment (into the resource group)
// ============================================================================

module infrastructure 'main.bicep' = {
  name: 'deploy-infrastructure-${environment}'
  scope: resourceGroup
  params: {
    environment: environment
    location: location
    projectName: projectName
    tags: tags
    imageTag: imageTag
    daprEnabled: daprEnabled
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    postgresAdminLogin: postgresAdminLogin
    postgresAdminPassword: postgresAdminPassword
    sqlServerAdminLogin: sqlServerAdminLogin
    sqlServerAdminPassword: sqlServerAdminPassword
    mysqlAdminLogin: mysqlAdminLogin
    mysqlAdminPassword: mysqlAdminPassword
    sqlAzureAdAdminObjectId: sqlAzureAdAdminObjectId
    sqlAzureAdAdminLogin: sqlAzureAdAdminLogin
    sqlAzureAdOnlyAuthentication: sqlAzureAdOnlyAuthentication
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup.name

@description('The location of the resource group')
output resourceGroupLocation string = resourceGroup.location

@description('Container Apps Environment ID')
output containerAppsEnvId string = infrastructure.outputs.containerAppsEnvId

@description('Container Apps Environment Name')
output containerAppsEnvName string = infrastructure.outputs.containerAppsEnvName

@description('Container Apps Environment Default Domain')
output containerAppsEnvDomain string = infrastructure.outputs.containerAppsEnvDomain

@description('Container Registry login server')
output acrLoginServer string = infrastructure.outputs.acrLoginServer

@description('Key Vault URI')
output keyVaultUri string = infrastructure.outputs.keyVaultUri

@description('Managed Identity Client ID')
output managedIdentityClientId string = infrastructure.outputs.managedIdentityClientId

@description('Service Bus Namespace')
output serviceBusNamespace string = infrastructure.outputs.serviceBusNamespace

@description('Redis Host Name')
output redisHostName string = infrastructure.outputs.redisHostName

@description('Cosmos DB Account Name')
output cosmosDbAccountName string = infrastructure.outputs.cosmosDbAccountName

@description('PostgreSQL Server FQDN')
output postgresqlFqdn string = infrastructure.outputs.postgresqlFqdn

@description('SQL Server FQDN')
output sqlServerFqdn string = infrastructure.outputs.sqlServerFqdn

@description('MySQL Server FQDN')
output mysqlFqdn string = infrastructure.outputs.mysqlFqdn
