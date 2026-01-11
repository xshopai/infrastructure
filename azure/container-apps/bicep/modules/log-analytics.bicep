// ============================================================================
// Log Analytics Workspace Module
// Required for Container Apps monitoring and diagnostics
// ============================================================================

@description('Name of the Log Analytics workspace')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU for the workspace')
@allowed(['Free', 'PerGB2018', 'Standalone'])
param sku string = 'PerGB2018'

// ============================================================================
// Resources
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1 // No cap
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics Workspace ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Name')
output workspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace Customer ID')
output customerId string = logAnalyticsWorkspace.properties.customerId

#disable-next-line outputs-should-not-contain-secrets
@description('Log Analytics Workspace Primary Shared Key (used internally for Container Apps logging)')
output primarySharedKey string = logAnalyticsWorkspace.listKeys().primarySharedKey
