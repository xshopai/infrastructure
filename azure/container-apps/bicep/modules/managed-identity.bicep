// ============================================================================
// User-Assigned Managed Identity Module
// Provides identity for Container Apps to access Azure resources
// ============================================================================

@description('Name of the managed identity')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

// ============================================================================
// Resources
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

// ============================================================================
// Outputs
// ============================================================================

@description('Managed Identity Resource ID')
output id string = managedIdentity.id

@description('Managed Identity Principal ID (Object ID)')
output principalId string = managedIdentity.properties.principalId

@description('Managed Identity Client ID')
output clientId string = managedIdentity.properties.clientId

@description('Managed Identity Name')
output name string = managedIdentity.name
