// =============================================================================
// Azure Playwright Testing - Workspace + Storage for Test Results
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

// =============================================================================
// Variables
// =============================================================================

var playwrightAccountName = 'pw-${resourcePrefix}'
// Storage names: 3-24 chars, lowercase alphanumeric only
var storageNameRaw = replace('stpw${resourcePrefix}', '-', '')
var storageName = length(storageNameRaw) > 24 ? substring(storageNameRaw, 0, 24) : storageNameRaw

// =============================================================================
// Resources
// =============================================================================

// Azure Playwright Testing workspace
resource playwrightAccount 'Microsoft.AzurePlaywrightService/accounts@2024-12-01' = {
  name: playwrightAccountName
  location: location
  tags: tags
  properties: {
    regionalAffinity: 'Enabled'
    scalableExecution: 'Enabled'
    reporting: 'Enabled'
  }
}

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

// =============================================================================
// Outputs
// =============================================================================

// Extract workspace GUID from the dashboard URI returned by Azure
// Format: https://playwright.microsoft.com/workspaces/<guid>
var workspaceGuid = last(split(playwrightAccount.properties.dashboardUri, '/'))

output playwrightAccountName string = playwrightAccount.name
output playwrightDashboardUrl string = playwrightAccount.properties.dashboardUri
output playwrightServiceUrl string = 'https://${location}.api.playwright.microsoft.com/accounts/${workspaceGuid}'
output playwrightWorkspaceId string = playwrightAccount.id
output storageAccountName string = storageAccount.name
output resultsContainerName string = resultsContainer.name
