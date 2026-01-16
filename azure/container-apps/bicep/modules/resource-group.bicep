// ============================================================================
// Resource Group Module
// ============================================================================
// Creates a resource group with configurable location
// Default location: Sweden Central (configurable for any Azure region)
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the resource group')
param name string

@description('Azure region for the resource group. Default: Sweden Central')
@allowed([
  'swedencentral'
  'westeurope'
  'northeurope'
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westus3'
  'centralus'
  'uksouth'
  'ukwest'
  'australiaeast'
  'southeastasia'
  'japaneast'
  'koreacentral'
  'canadacentral'
  'brazilsouth'
  'germanywestcentral'
  'norwayeast'
  'switzerlandnorth'
])
param location string = 'swedencentral'

@description('Tags to apply to the resource group')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: name
  location: location
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the resource group')
output name string = rg.name

@description('The location of the resource group')
output location string = rg.location

@description('The resource ID of the resource group')
output resourceId string = rg.id
