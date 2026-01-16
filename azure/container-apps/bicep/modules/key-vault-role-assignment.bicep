// ========================================
// Key Vault Role Assignment Module
// ========================================
// Assigns an Azure RBAC role to a principal (user, group, service principal, managed identity)
// for a specific Key Vault resource.
//
// Common Role Definition IDs:
// - Key Vault Secrets User: 4633458b-17de-408a-b874-0445c86b69e6 (read secrets)
// - Key Vault Secrets Officer: b86a8fe4-44ce-4948-aee5-eccb2c155cd7 (full secret management)
// - Key Vault Administrator: 00482a5a-887f-4fb3-b061-3bfc1c3d2ba9 (full control)
// ========================================

@description('Name of the existing Key Vault')
param keyVaultName string

@description('Principal ID (object ID) of the user, group, service principal, or managed identity')
param principalId string

@description('Role Definition ID (GUID) for the RBAC role to assign')
param roleDefinitionId string

@description('Principal type: ServicePrincipal, User, or Group')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

// ========================================
// Resources
// ========================================

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Assign the role at Key Vault scope
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

// ========================================
// Outputs
// ========================================

@description('Role assignment resource ID')
output roleAssignmentId string = roleAssignment.id

@description('Role assignment name (GUID)')
output roleAssignmentName string = roleAssignment.name
