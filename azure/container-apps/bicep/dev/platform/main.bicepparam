// ========================================
// Development Environment Parameters
// ========================================
// Purpose: Parameter values for dev environment platform infrastructure
// Usage: az deployment sub create --location swedencentral --template-file main.bicep --parameters main.bicepparam
// ========================================

using './main.bicep'

// ========================================
// Environment Configuration
// ========================================

param location = 'swedencentral'
param environment = 'dev'

// ========================================
// Tags
// ========================================

param tags = {
  Environment: 'dev'
  Project: 'xshopai'
  ManagedBy: 'Bicep'
  CostCenter: 'Engineering'
  Owner: 'DevOps Team'
  Criticality: 'Low'
}

// ========================================
// Log Analytics
// ========================================

// Dev environment: 30 days retention (cost optimization)
param logAnalyticsRetentionDays = 30

// ========================================
// PostgreSQL Configuration
// ========================================

// PostgreSQL admin username (shared across all databases)
param postgresAdminUsername = 'xshopadmin'

// PostgreSQL version
param postgresVersion = '16'

// NOTE: postgresAdminPassword is a secure parameter
// DO NOT commit actual passwords to source control!
// This placeholder will be overridden at deployment time via:
//   - GitHub Actions secret: secrets.POSTGRES_ADMIN_PASSWORD
//   - Azure Key Vault reference
//   - Command line parameter (for testing only)
param postgresAdminPassword = '' // Empty placeholder - MUST be provided at deployment

// ========================================
// Redis Configuration
// ========================================

// Redis SKU: Basic, Standard, or Premium
param redisSku = 'Basic'

// Redis family: C (Basic/Standard) or P (Premium)
param redisFamily = 'C'

// Redis capacity: 0-6 (size tier within family)
// C0 = 250MB, C1 = 1GB, C2 = 2.5GB, etc.
param redisCapacity = 0

// ========================================
// Service Bus Configuration
// ========================================

// Service Bus SKU: Basic, Standard, or Premium
param serviceBusSku = 'Standard'

// ========================================
// SQL Server Configuration
// ========================================

// SQL Server admin username
param sqlAdminUsername = 'sqladmin'

// SQL Server version
param sqlVersion = '12.0'

// NOTE: sqlAdminPassword is a secure parameter
// DO NOT commit actual passwords to source control!
// This placeholder will be overridden at deployment time via:
//   - GitHub Actions secret: secrets.SQL_ADMIN_PASSWORD
//   - Azure Key Vault reference
//   - Command line parameter (for testing only)
param sqlAdminPassword = '' // Empty placeholder - MUST be provided at deployment

// ========================================
// MySQL Configuration
// ========================================

// MySQL admin username
param mysqlAdminUsername = 'mysqladmin'

// MySQL version
param mysqlVersion = '8.0.21'

// NOTE: mysqlAdminPassword is a secure parameter
// DO NOT commit actual passwords to source control!
// This placeholder will be overridden at deployment time via:
//   - GitHub Actions secret: secrets.MYSQL_ADMIN_PASSWORD
//   - Azure Key Vault reference
//   - Command line parameter (for testing only)
param mysqlAdminPassword = '' // Empty placeholder - MUST be provided at deployment

// ========================================
// Deployment Notes
// ========================================
/*
To deploy this environment:

1. Validate template:
   az deployment sub validate \
     --location swedencentral \
     --template-file main.bicep \
     --parameters main.bicepparam

2. Deploy (What-If first):
   az deployment sub what-if \
     --location swedencentral \
     --template-file main.bicep \
     --parameters main.bicepparam

3. Deploy (actual):
   az deployment sub create \
     --name "xshopai-dev-$(date +%Y%m%d-%H%M%S)" \
     --location swedencentral \
     --template-file main.bicep \
     --parameters main.bicepparam

4. Get outputs:
   az deployment sub show \
     --name <deployment-name> \
     --query properties.outputs

Expected Resources Created:
- Resource Group: rg-xshopai-dev
- Log Analytics: log-xshopai-dev
- Container Apps Environment: cae-xshopai-dev
- Managed Identity: id-xshopai-dev
- Key Vault: kv-xshopai-dev

Database Infrastructure:
- PostgreSQL Servers (3):
  * psql-xshopai-product-dev (for product-service)
  * psql-xshopai-user-dev (for user-service)
  * psql-xshopai-order-dev (for order-service)
- Cosmos DB: cosmos-xshopai-dev (MongoDB API, shared)
- SQL Server: sql-xshopai-dev
  * SQL Database: sqldb-order-dev (for order-service)
  * SQL Database: sqldb-payment-dev (for payment-service)
- MySQL Server: mysql-xshopai-cart-dev (for cart-service)

Messaging & Caching:
- Service Bus: sb-xshopai-dev (topics, queues, subscriptions)
- Redis Cache: redis-xshopai-dev (C0 Basic, 250MB)

Estimated Monthly Cost (Dev): ~$350-450 USD
  - Container Apps Environment: ~$50
  - PostgreSQL (3x B1ms): ~$30 each = $90
  - Cosmos DB (serverless): ~$25-50
  - SQL Server + 2 DBs (Basic): ~$10
  - MySQL (B1ms): ~$30
  - Service Bus (Standard): ~$10
  - Redis (C0 Basic): ~$20
  - Log Analytics: ~$20
  - Key Vault: ~$5
*/
