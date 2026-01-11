// ============================================================================
// Azure Container Apps Environment Module
// Managed environment for running Container Apps with Dapr support
// ============================================================================

@description('Name of the Container Apps Environment')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Log Analytics Workspace Name')
param logAnalyticsWorkspaceName string

@description('Enable zone redundancy (requires Premium)')
param zoneRedundant bool = false

@description('Workload profile type')
@allowed(['Consumption', 'D4', 'D8', 'D16', 'D32', 'E4', 'E8', 'E16', 'E32'])
param workloadProfileType string = 'Consumption'

// ============================================================================
// Resources
// ============================================================================

// Reference existing Log Analytics workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: zoneRedundant
    workloadProfiles: workloadProfileType == 'Consumption' ? [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ] : [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'Dedicated'
        workloadProfileType: workloadProfileType
        minimumCount: 1
        maximumCount: 3
      }
    ]
    peerAuthentication: {
      mtls: {
        enabled: true
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Container Apps Environment Resource ID')
output id string = containerAppsEnvironment.id

@description('Container Apps Environment Name')
output name string = containerAppsEnvironment.name

@description('Container Apps Environment Default Domain')
output defaultDomain string = containerAppsEnvironment.properties.defaultDomain

@description('Container Apps Environment Static IP')
output staticIp string = containerAppsEnvironment.properties.staticIp
