// ============================================================================
// Container Apps Environment Module
// ============================================================================
// Creates an Azure Container Apps Environment for hosting container apps
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Container Apps Environment')
param name string

@description('Azure region for the environment. Default: Sweden Central')
param location string = 'swedencentral'

@description('Resource ID of the Log Analytics workspace for logs')
param logAnalyticsWorkspaceId string = ''

@description('Enable internal-only ingress (no public endpoint)')
param internalOnly bool = false

@description('Enable zone redundancy (requires Premium tier)')
param zoneRedundant bool = false

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var logAnalyticsConfig = empty(logAnalyticsWorkspaceId) ? {} : {
  logAnalyticsConfiguration: {
    customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
    sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
  }
}

// ============================================================================
// Resources
// ============================================================================

resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: name
  location: location
  properties: {
    appLogsConfiguration: !empty(logAnalyticsWorkspaceId) ? {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    } : {
      destination: 'azure-monitor'
    }
    zoneRedundant: zoneRedundant
    vnetConfiguration: internalOnly ? {
      internal: true
    } : null
  }
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the Container Apps Environment')
output name string = environment.name

@description('The resource ID of the environment')
output resourceId string = environment.id

@description('The default domain of the environment')
output defaultDomain string = environment.properties.defaultDomain

@description('The static IP of the environment')
output staticIp string = environment.properties.staticIp
