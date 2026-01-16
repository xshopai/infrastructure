// ============================================================================
// ACR Resource Module (Bootstrap Helper)
// ============================================================================
// Purpose: Deploys Azure Container Registry resource
// Note: This is a separate file to keep bootstrap template clean
// ============================================================================

targetScope = 'resourceGroup'

// Parameters
@description('Name of the Azure Container Registry')
param registryName string

@description('Azure region for the registry')
param location string

@description('ACR SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string

@description('Tags to apply to the registry')
param tags object

@description('Enable anonymous pull access')
param enableAnonymousPull bool

@description('Enable admin user')
param enableAdminUser bool

@description('Enable public network access')
param publicNetworkAccess bool

@description('Enable zone redundancy (Premium SKU only)')
param enableZoneRedundancy bool

// ============================================================================
// Azure Container Registry Resource
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: enableAdminUser
    anonymousPullEnabled: enableAnonymousPull
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    zoneRedundancy: (sku == 'Premium' && enableZoneRedundancy) ? 'Enabled' : 'Disabled'
    
    // Network rules (allow all by default for bootstrap simplicity)
    networkRuleSet: publicNetworkAccess ? {
      defaultAction: 'Allow'
    } : null
    
    // Encryption (default)
    encryption: {
      status: 'disabled'
    }
    
    // Data endpoint (Premium SKU only)
    dataEndpointEnabled: sku == 'Premium'
    
    // Retention policy (Premium SKU only)
    policies: sku == 'Premium' ? {
      retentionPolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
        type: 'Notary'
      }
    } : null
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the Azure Container Registry')
output registryName string = containerRegistry.name

@description('The login server URL for the ACR')
output loginServer string = containerRegistry.properties.loginServer

@description('The resource ID of the ACR')
output registryId string = containerRegistry.id

@description('The principal ID (if managed identity is enabled)')
output principalId string = containerRegistry.identity.principalId

@description('The SKU of the registry')
output sku string = containerRegistry.sku.name
