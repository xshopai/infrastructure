// =================================================================
// Bootstrap Infrastructure Parameters - Development Environment
// =================================================================

using './main.bicep'

// Environment Configuration
param location = 'eastus'
param environment = 'dev'
param projectName = 'xshopai'

// ACR Configuration
param acrSku = 'Standard'
param acrAdminUserEnabled = false
param acrAnonymousPullEnabled = false

// Resource Tags
param tags = {
  Project: 'xshopai'
  ManagedBy: 'Bicep'
  Environment: 'dev'
  Purpose: 'Bootstrap Infrastructure'
  DeployedBy: 'GitHub Actions'
  CostCenter: 'Engineering'
}
