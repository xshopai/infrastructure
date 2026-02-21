// =============================================================================
// Key Vault - Secrets storage with diagnostic logging
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Resource tags')
param tags object

// JWT Configuration
@secure()
param jwtSecret string
param jwtAlgorithm string
param jwtIssuer string
param jwtAudience string
param jwtExpiresIn string

// Database Credentials
param postgresAdminUser string
@secure()
param postgresAdminPassword string
param mysqlAdminUser string
@secure()
param mysqlAdminPassword string
param sqlAdminUser string
@secure()
param sqlAdminPassword string

// RabbitMQ
param rabbitmqUser string
@secure()
param rabbitmqPassword string
param rabbitmqHost string

// Redis
param redisHost string
@secure()
param redisKey string

// Monitoring
param appInsightsConnectionString string
@secure()
param appInsightsKey string

// Database Hosts
param postgresHost string
param mysqlHost string
param sqlHost string
@secure()
param cosmosConnectionString string

// Service Tokens
@secure()
param adminServiceToken string
@secure()
param authServiceToken string
@secure()
param userServiceToken string
@secure()
param cartServiceToken string
@secure()
param orderServiceToken string
@secure()
param productServiceToken string
@secure()
param webBffToken string

// Azure OpenAI
param openaiEndpoint string
param openaiDeployment string

// =============================================================================
// Variables
// =============================================================================

var keyVaultName = 'kv-${resourcePrefix}'

// Extract database names from Cosmos connection string
var cosmosDbPattern = 'mongodb://'
var userMongoUri = '${cosmosConnectionString}user_service_db?retryWrites=true&w=majority'
var productMongoUri = '${cosmosConnectionString}product_service_db?retryWrites=true&w=majority'
var reviewMongoUri = '${cosmosConnectionString}review_service_db?retryWrites=true&w=majority'

// Build database connection strings
var auditPostgresUrl = 'postgresql://${postgresAdminUser}:${postgresAdminPassword}@${postgresHost}:5432/audit_service_db?sslmode=require'
var orderProcessorPostgresUrl = 'postgresql://${postgresAdminUser}:${postgresAdminPassword}@${postgresHost}:5432/order_processor_db?sslmode=require'
var inventoryMysqlConnection = 'Server=${mysqlHost};Database=inventory_service_db;Uid=${mysqlAdminUser};Pwd=${mysqlAdminPassword};SslMode=Required;'
var orderSqlConnection = 'Server=tcp:${sqlHost},1433;Database=order_service_db;User ID=${sqlAdminUser};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var paymentSqlConnection = 'Server=tcp:${sqlHost},1433;Database=payment_service_db;User ID=${sqlAdminUser};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var rabbitmqUrl = 'amqp://${rabbitmqUser}:${rabbitmqPassword}@${rabbitmqHost}:5672'

// =============================================================================
// Resources
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: false // Use access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true // Cannot be disabled once enabled
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: []
  }
}

// Diagnostic settings for Key Vault
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${keyVaultName}'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// =============================================================================
// Secrets
// =============================================================================

// JWT Configuration
resource secretJwtSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-secret'
  properties: { value: jwtSecret }
}

resource secretJwtAlgorithm 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-algorithm'
  properties: { value: jwtAlgorithm }
}

resource secretJwtIssuer 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-issuer'
  properties: { value: jwtIssuer }
}

resource secretJwtAudience 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-audience'
  properties: { value: jwtAudience }
}

resource secretJwtExpiresIn 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-expires-in'
  properties: { value: jwtExpiresIn }
}

// Database Credentials
resource secretPostgresUser 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgres-admin-user'
  properties: { value: postgresAdminUser }
}

resource secretPostgresPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgres-admin-password'
  properties: { value: postgresAdminPassword }
}

resource secretMysqlUser 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-admin-user'
  properties: { value: mysqlAdminUser }
}

resource secretMysqlPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-admin-password'
  properties: { value: mysqlAdminPassword }
}

resource secretSqlUser 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-user'
  properties: { value: sqlAdminUser }
}

resource secretSqlPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: { value: sqlAdminPassword }
}

// RabbitMQ
resource secretRabbitmqUser 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'rabbitmq-user'
  properties: { value: rabbitmqUser }
}

resource secretRabbitmqPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'rabbitmq-password'
  properties: { value: rabbitmqPassword }
}

resource secretRabbitmqHost 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'rabbitmq-host'
  properties: { value: rabbitmqHost }
}

resource secretRabbitmqUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'rabbitmq-url'
  properties: { value: rabbitmqUrl }
}

// Redis
resource secretRedisHost 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-host'
  properties: { value: redisHost }
}

resource secretRedisKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-key'
  properties: { value: redisKey }
}

// Monitoring
resource secretAppInsightsConnection 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'appinsights-connection-string'
  properties: { value: appInsightsConnectionString }
}

resource secretAppInsightsKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'appinsights-instrumentation-key'
  properties: { value: appInsightsKey }
}

// Database Connection Strings
resource secretUserMongoUri 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'user-service-mongodb-uri'
  properties: { value: userMongoUri }
}

resource secretProductMongoUri 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'product-service-mongodb-uri'
  properties: { value: productMongoUri }
}

resource secretReviewMongoUri 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'review-service-mongodb-uri'
  properties: { value: reviewMongoUri }
}

resource secretAuditPostgresUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'audit-service-postgres-url'
  properties: { value: auditPostgresUrl }
}

resource secretOrderProcessorPostgresUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'order-processor-service-postgres-url'
  properties: { value: orderProcessorPostgresUrl }
}

resource secretInventoryMysqlConnection 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'inventory-service-mysql-server'
  properties: { value: inventoryMysqlConnection }
}

resource secretOrderSqlConnection 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'order-service-sql-connection'
  properties: { value: orderSqlConnection }
}

resource secretPaymentSqlConnection 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'payment-service-sql-connection'
  properties: { value: paymentSqlConnection }
}

// Service Tokens
resource secretAdminServiceToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'admin-service-token'
  properties: { value: adminServiceToken }
}

resource secretAuthServiceToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'auth-service-token'
  properties: { value: authServiceToken }
}

resource secretUserServiceToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'user-service-token'
  properties: { value: userServiceToken }
}

resource secretCartServiceToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cart-service-token'
  properties: { value: cartServiceToken }
}

resource secretOrderServiceToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'order-service-token'
  properties: { value: orderServiceToken }
}

resource secretProductServiceToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'product-service-token'
  properties: { value: productServiceToken }
}

resource secretWebBffToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'web-bff-token'
  properties: { value: webBffToken }
}

// Azure OpenAI
resource secretOpenaiEndpoint 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'chat-service-openai-endpoint'
  properties: { value: openaiEndpoint }
}

resource secretOpenaiDeployment 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'chat-service-openai-deployment'
  properties: { value: openaiDeployment }
}

// =============================================================================
// Outputs
// =============================================================================

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
