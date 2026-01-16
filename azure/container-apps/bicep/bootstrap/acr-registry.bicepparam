// ============================================================================
// Parameters for Bootstrap ACR Deployment
// ============================================================================

using './acr-registry.bicep'

// ACR Configuration
param registryName = 'xshopaimodules'
param location = 'eastus'
param resourceGroupName = 'xshopai-shared-rg'

// SKU Configuration
// - Basic: For dev/test, no geo-replication
// - Standard: For production, supports webhooks
// - Premium: For enterprise, supports geo-replication, private endpoints
param sku = 'Standard'

// Security Configuration
param enableAnonymousPull = false  // Require authentication (recommended)
param enableAdminUser = false      // Use RBAC instead (recommended)
param publicNetworkAccess = true   // Allow public access (change to false for private)
param enableZoneRedundancy = false // Only for Premium SKU

// Tags
param tags = {
  Environment: 'Shared'
  ManagedBy: 'Bicep'
  Purpose: 'Bicep Module Registry'
  Project: 'xshopai'
  CostCenter: 'Engineering'
  DeployedBy: 'Bootstrap'
  DeploymentDate: '2026-01-16'
}
