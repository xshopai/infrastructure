// =============================================================================
// App Service Plan - P3V3 Linux (Production Grade)
// =============================================================================
// P3V3: 8 vCPU, 32 GB RAM, 99.95% SLA, auto-scale capable
// IMPORTANT: Do not use B1/S1 for this workload - 14 apps need Premium tier
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

@description('App Service Plan SKU')
@allowed(['P1V3', 'P2V3', 'P3V3'])
param sku string = 'P3V3'

// =============================================================================
// Variables
// =============================================================================

var appServicePlanName = 'asp-${resourcePrefix}'

// =============================================================================
// Resources
// =============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: 'PremiumV3'
    size: sku
    family: 'Pv3'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    zoneRedundant: false
  }
}

// =============================================================================
// Outputs
// =============================================================================

output appServicePlanId string = appServicePlan.id
output appServicePlanName string = appServicePlan.name
output appServicePlanKind string = appServicePlan.kind
