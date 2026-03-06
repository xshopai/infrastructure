// =============================================================================
// Playwright Workspaces (Azure App Testing) + Storage for Test Results
// =============================================================================
// Uses Microsoft.LoadTestService/playwrightWorkspaces (replaces retired
// Microsoft.AzurePlaywrightService/accounts which was sunset 2026-03-08)

targetScope = 'resourceGroup'

@description('Azure region for storage and default resources')
param location string

@description('Azure region for Playwright Workspace (check availability)')
param playwrightLocation string = 'westeurope'

@description('Resource naming prefix (xshopai-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

@description('Principal ID of the GitHub Actions OIDC service principal (for Storage Blob Data Contributor)')
param githubActionsPrincipalId string = ''

// =============================================================================
// Variables
// =============================================================================

// Playwright workspace names: alphanumeric + hyphens, 3-24 chars, ^[a-zA-Z0-9-]{3,24}$
var playwrightWorkspaceName = 'pw-${resourcePrefix}'
// Storage names: 3-24 chars, lowercase alphanumeric only
var storageNameRaw = replace('stpw${resourcePrefix}', '-', '')
var storageName = length(storageNameRaw) > 24 ? substring(storageNameRaw, 0, 24) : storageNameRaw

// Storage Blob Data Contributor role definition ID
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// =============================================================================
// Resources
// =============================================================================

// Storage Account for Playwright test result artifacts
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource resultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'playwright-results'
  properties: {
    publicAccess: 'None'
  }
}

// Lifecycle policy — auto-delete results after 90 days
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'cleanup-old-results'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [ 'blockBlob' ]
              prefixMatch: [ 'playwright-results/' ]
            }
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 90
                }
              }
            }
          }
        }
      ]
    }
  }
}

// Playwright Workspace (Azure App Testing)
// Using 2026-01-01-preview for storageUri + reporting support (not in 2025-09-01 GA)
// System-assigned managed identity is required for the workspace to upload
// test result artifacts to the linked storage account.
resource playwrightWorkspace 'Microsoft.LoadTestService/playwrightWorkspaces@2026-01-01-preview' = {
  name: playwrightWorkspaceName
  location: playwrightLocation
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    regionalAffinity: 'Enabled'
    localAuth: 'Disabled'
    storageUri: storageAccount.properties.primaryEndpoints.blob
  }
}

// Storage Blob Data Contributor for the Playwright workspace's managed identity
// The workspace identity uploads test result artifacts to the linked storage account
resource workspaceStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, playwrightWorkspace.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: playwrightWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor for the GitHub Actions OIDC service principal
// Belt-and-suspenders: the CI runner identity also needs access for direct uploads
resource ciRunnerStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(githubActionsPrincipalId)) {
  name: guid(storageAccount.id, githubActionsPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: githubActionsPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

output playwrightWorkspaceName string = playwrightWorkspace.name
output playwrightServiceUrl string = playwrightWorkspace.properties.dataplaneUri
output playwrightWorkspaceId string = playwrightWorkspace.properties.workspaceId
output storageAccountName string = storageAccount.name
output resultsContainerName string = resultsContainer.name
