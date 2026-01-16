// ============================================================================
// Key Vault Secrets Module
// Store secrets in Azure Key Vault
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Key Vault')
param keyVaultName string

@description('Array of secrets to store. Each object should have: name (required), value (required), contentType (optional)')
param secrets array

// ============================================================================
// Resources
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource keyVaultSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for secret in secrets: {
  parent: keyVault
  name: secret.name
  properties: {
    value: secret.value
    contentType: secret.?contentType ?? 'text/plain'
  }
}]

// ============================================================================
// Outputs
// ============================================================================

@description('Names of created secrets')
output secretNames array = [for (secret, i) in secrets: keyVaultSecrets[i].name]

@description('Number of secrets created')
#disable-next-line outputs-should-not-contain-secrets
output secretCount int = length(secrets)
