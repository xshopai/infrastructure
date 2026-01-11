// ============================================================================
// Staging Environment Parameters
// ============================================================================
using '../main.bicep'

param environment = 'staging'
param location = 'uksouth'
param projectName = 'xshopai'

// Database credentials - Set via GitHub Actions secrets
param postgresAdminLogin = 'xshopaiadmin'
param postgresAdminPassword = '' // Set via GitHub secret: POSTGRES_ADMIN_PASSWORD

param sqlServerAdminLogin = 'xshopaiadmin'
param sqlServerAdminPassword = '' // Set via GitHub secret: SQL_SERVER_ADMIN_PASSWORD

param mysqlAdminLogin = 'xshopaiadmin'
param mysqlAdminPassword = '' // Set via GitHub secret: MYSQL_ADMIN_PASSWORD
