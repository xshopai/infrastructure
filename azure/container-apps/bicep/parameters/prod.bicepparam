// ============================================================================
// Production Environment Parameters
// ============================================================================
using '../main.bicep'

param environment = 'prod'
param location = 'uksouth'
param projectName = 'xshopai'

param imageTag = 'latest'
param daprEnabled = true
param minReplicas = 2
param maxReplicas = 10

// Database credentials - Set via GitHub Actions secrets
param postgresAdminLogin = 'xshopaiadmin'
param postgresAdminPassword = '' // Set via GitHub secret: POSTGRES_ADMIN_PASSWORD

param sqlServerAdminLogin = 'xshopaiadmin'
param sqlServerAdminPassword = '' // Set via GitHub secret: SQL_SERVER_ADMIN_PASSWORD

param mysqlAdminLogin = 'xshopaiadmin'
param mysqlAdminPassword = '' // Set via GitHub secret: MYSQL_ADMIN_PASSWORD
