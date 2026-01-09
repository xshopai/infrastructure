// ============================================================================
// Key Vault Secrets Module
// Stores application secrets in Key Vault
// ============================================================================

@description('Name of the Key Vault')
param keyVaultName string

@description('Array of secrets to store - each object should have name and value properties')
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
    contentType: 'text/plain'
  }
}]

// ============================================================================
// Outputs
// ============================================================================

@description('Number of secrets created')
#disable-next-line outputs-should-not-contain-secrets
output secretCount int = length(secrets)
