// ============================================================================
// Staging Environment Parameters
// ============================================================================
using 'main.bicep'

param environment = 'staging'
param location = 'uksouth'
param projectName = 'xshopai'

param imageTag = 'latest'
param daprEnabled = true
param minReplicas = 1
param maxReplicas = 5

// These will be overridden by GitHub Actions secrets
param postgresAdminLogin = 'xshopaiadmin'
param postgresAdminPassword = '' // Set via GitHub secret
