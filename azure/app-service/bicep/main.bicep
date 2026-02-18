// Main Bicep template for xshopai App Service infrastructure
// Orchestrates all modules in the correct dependency order
targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Environment name (development or production)')
@allowed([
  'development'
  'production'
])
param environment string = 'development'

@description('Azure region for all resources')
param location string = 'swedencentral'

@description('Organization name')
param orgName string = 'xshopai'

@description('Pipeline platform (gh/ado)')
param pipeline string = 'gh'

@secure()
@description('Database admin password - passed from workflow (not auto-generated for idempotency)')
param dbAdminPassword string

// ============================================================================
// VARIABLES
// ============================================================================

var shortEnv = substring(environment, 0, 3)
var resourceGroupName = 'rg-${orgName}-${pipeline}-${environment}'
var tags = {
  Environment: environment
  Project: orgName
  ManagedBy: 'Bicep'
  DeployedBy: 'GitHub Actions'
}

// ============================================================================
// RESOURCE GROUP
// ============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// FOUNDATIONAL MODULES (no dependencies)
// ============================================================================

// Container Registry - shared across environments
module acr './modules/acr.bicep' = {
  name: 'acr-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    orgName: orgName
    pipeline: pipeline
    tags: tags
  }
}

// Monitoring (Application Insights + Log Analytics)
module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    tags: tags
  }
}

// Key Vault (secrets store)
module keyVault './modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    tags: tags
  }
}

// App Service Plan (compute)
module appServicePlan './modules/app-service-plan.bicep' = {
  name: 'app-service-plan-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    tags: tags
  }
}

// ============================================================================
// DATABASE MODULES (depend on Key Vault)
// ============================================================================

// Cosmos DB (MongoDB API) - for Node.js services
module cosmos './modules/cosmos.bicep' = {
  name: 'cosmos-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    keyVaultName: keyVault.outputs.keyVaultName
    tags: tags
  }
}

// PostgreSQL - for notification-service
module postgres './modules/postgres.bicep' = {
  name: 'postgres-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    keyVaultName: keyVault.outputs.keyVaultName
    adminPassword: dbAdminPassword
    tags: tags
  }
}

// MySQL - for review-service, admin-service
module mysql './modules/mysql.bicep' = {
  name: 'mysql-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    keyVaultName: keyVault.outputs.keyVaultName
    adminPassword: dbAdminPassword
    tags: tags
  }
}

// SQL Server - for order-service, payment-service, cart-service
module sqlserver './modules/sqlserver.bicep' = {
  name: 'sqlserver-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    keyVaultName: keyVault.outputs.keyVaultName
    adminPassword: dbAdminPassword
    tags: tags
  }
}

// ============================================================================
// MESSAGING MODULES
// ============================================================================

// Redis Cache
module redis './modules/redis.bicep' = {
  name: 'redis-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    tags: tags
  }
}

// RabbitMQ (Container Instance)
module rabbitmq './modules/rabbitmq.bicep' = {
  name: 'rabbitmq-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    tags: tags
  }
}

// ============================================================================
// APP SERVICES - Individual modules per service
// ============================================================================

// ---------- Cosmos DB Services ----------

module authService './modules/services/auth-service.bicep' = {
  name: 'auth-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [cosmos, redis, rabbitmq]
}

module userService './modules/services/user-service.bicep' = {
  name: 'user-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [cosmos, redis, rabbitmq]
}

module productService './modules/services/product-service.bicep' = {
  name: 'product-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [cosmos, redis, rabbitmq]
}

module inventoryService './modules/services/inventory-service.bicep' = {
  name: 'inventory-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [cosmos, redis, rabbitmq]
}

module auditService './modules/services/audit-service.bicep' = {
  name: 'audit-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [cosmos, redis, rabbitmq]
}

// ---------- PostgreSQL Services ----------

module notificationService './modules/services/notification-service.bicep' = {
  name: 'notification-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    postgresHost: postgres.outputs.postgresHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [postgres, redis, rabbitmq]
}

// ---------- MySQL Services ----------

module reviewService './modules/services/review-service.bicep' = {
  name: 'review-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    mysqlHost: mysql.outputs.mysqlHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [mysql, redis, rabbitmq]
}

module adminServiceModule './modules/services/admin-service.bicep' = {
  name: 'admin-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    mysqlHost: mysql.outputs.mysqlHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [mysql, redis, rabbitmq]
}

// ---------- SQL Server Services ----------

module cartService './modules/services/cart-service.bicep' = {
  name: 'cart-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    sqlServerHost: sqlserver.outputs.sqlServerHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [sqlserver, redis, rabbitmq]
}

module paymentService './modules/services/payment-service.bicep' = {
  name: 'payment-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    sqlServerHost: sqlserver.outputs.sqlServerHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [sqlserver, redis, rabbitmq]
}

module orderService './modules/services/order-service.bicep' = {
  name: 'order-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    sqlServerHost: sqlserver.outputs.sqlServerHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [sqlserver, redis, rabbitmq]
}

module orderProcessorService './modules/services/order-processor-service.bicep' = {
  name: 'order-processor-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    sqlServerHost: sqlserver.outputs.sqlServerHost
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [sqlserver, redis, rabbitmq]
}

// ---------- Stateless Services (No Database) ----------

module chatService './modules/services/chat-service.bicep' = {
  name: 'chat-service-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    redisHost: redis.outputs.redisHost
    rabbitMQHost: rabbitmq.outputs.rabbitMQHost
  }
  dependsOn: [redis, rabbitmq]
}

module webBff './modules/services/web-bff.bicep' = {
  name: 'web-bff-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
    redisHost: redis.outputs.redisHost
  }
  dependsOn: [redis]
}

module customerUi './modules/services/customer-ui.bicep' = {
  name: 'customer-ui-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
  }
}

module adminUi './modules/services/admin-ui.bicep' = {
  name: 'admin-ui-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    shortEnv: shortEnv
    appServicePlanId: appServicePlan.outputs.planId
    acrLoginServer: acr.outputs.acrLoginServer
    applicationInsightsKey: monitoring.outputs.instrumentationKey
    tags: tags
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Infrastructure
output resourceGroupName string = resourceGroupName
output acrName string = acr.outputs.acrName
output acrLoginServer string = acr.outputs.acrLoginServer
output keyVaultName string = keyVault.outputs.keyVaultName
output appInsightsName string = monitoring.outputs.appInsightsName
output appServicePlanName string = appServicePlan.outputs.planName

// Databases
output cosmosEndpoint string = cosmos.outputs.cosmosEndpoint
output postgresHost string = postgres.outputs.postgresHost
output mysqlHost string = mysql.outputs.mysqlHost
output sqlServerHost string = sqlserver.outputs.sqlServerHost

// Messaging
output redisHost string = redis.outputs.redisHost
output rabbitMQHost string = rabbitmq.outputs.rabbitMQHost

// Service URLs
output authServiceUrl string = authService.outputs.appServiceUrl
output userServiceUrl string = userService.outputs.appServiceUrl
output productServiceUrl string = productService.outputs.appServiceUrl
output inventoryServiceUrl string = inventoryService.outputs.appServiceUrl
output auditServiceUrl string = auditService.outputs.appServiceUrl
output notificationServiceUrl string = notificationService.outputs.appServiceUrl
output reviewServiceUrl string = reviewService.outputs.appServiceUrl
output adminServiceUrl string = adminServiceModule.outputs.appServiceUrl
output cartServiceUrl string = cartService.outputs.appServiceUrl
output paymentServiceUrl string = paymentService.outputs.appServiceUrl
output orderServiceUrl string = orderService.outputs.appServiceUrl
output orderProcessorServiceUrl string = orderProcessorService.outputs.appServiceUrl
output chatServiceUrl string = chatService.outputs.appServiceUrl
output webBffUrl string = webBff.outputs.appServiceUrl
output customerUiUrl string = customerUi.outputs.appServiceUrl
output adminUiUrl string = adminUi.outputs.appServiceUrl
