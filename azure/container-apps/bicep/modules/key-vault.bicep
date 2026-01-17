// ============================================================================
// Azure Key Vault Module
// ============================================================================
// Creates an Azure Key Vault for secrets management
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Key Vault (must be globally unique)')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region for the Key Vault. Default: Sweden Central')
param location string = 'swedencentral'

@description('SKU for the Key Vault')
@allowed([
  'standard'
  'premium'
])
param sku string = 'standard'

@description('Enable soft delete for the Key Vault')
param enableSoftDelete bool = true

@description('Number of days to retain soft-deleted secrets')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Enable purge protection (cannot be disabled once enabled)')
param enablePurgeProtection bool = true

@description('Enable RBAC authorization (recommended over access policies)')
param enableRbacAuthorization bool = true

@description('Tenant ID for the Key Vault')
param tenantId string = subscription().tenantId

@description('Access policies for the Key Vault (used when RBAC is disabled)')
param accessPolicies array = []

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: sku
    }
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection
    enableRbacAuthorization: enableRbacAuthorization
    accessPolicies: enableRbacAuthorization ? [] : accessPolicies
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the Key Vault')
output name string = keyVault.name

@description('The URI of the Key Vault')
output uri string = keyVault.properties.vaultUri

@description('The resource ID of the Key Vault')
output resourceId string = keyVault.id
