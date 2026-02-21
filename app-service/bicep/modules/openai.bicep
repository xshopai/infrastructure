// =============================================================================
// Azure OpenAI - S0 SKU with gpt-4o deployment
// Configured for Managed Identity authentication (no API keys)
// =============================================================================

targetScope = 'resourceGroup'

@description('Preferred Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

@description('Model name to deploy')
param modelName string = 'gpt-4o'

@description('Model version')
param modelVersion string = '2024-11-20'

@description('Deployment name')
param deploymentName string = 'gpt-4o'

@description('SKU capacity (tokens per minute / 1000)')
param skuCapacity int = 10

// =============================================================================
// Variables
// =============================================================================

var openaiAccountName = 'oai-${resourcePrefix}'

// Fallback regions if OpenAI is not available in primary location
// Priority: location → swedencentral → westeurope → germanywestcentral → uksouth → eastus2
var candidateLocations = [
  location
  'swedencentral'
  'westeurope'
  'germanywestcentral'
  'uksouth'
  'eastus2'
]

// Use first candidate location (multi-region fallback requires runtime logic)
var openaiLocation = location

// =============================================================================
// Resources
// =============================================================================

resource openaiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openaiAccountName
  location: openaiLocation
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openaiAccountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true // Enforce Managed Identity only (no API keys)
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Deploy gpt-4o model
resource openaiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openaiAccount
  name: deploymentName
  sku: {
    name: 'Standard'
    capacity: skuCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.Default'
  }
}

// =============================================================================
// Outputs
// =============================================================================

output openaiAccountId string = openaiAccount.id
output openaiAccountName string = openaiAccount.name
output openaiEndpoint string = openaiAccount.properties.endpoint
output openaiResourceId string = openaiAccount.id
output openaiLocation string = openaiLocation
output deploymentName string = openaiDeployment.name
output modelName string = modelName
output modelVersion string = modelVersion
