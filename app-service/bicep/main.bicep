// =============================================================================
// xShopAI - Azure App Service Infrastructure (Bicep)
// =============================================================================
// Main orchestrator - deploys all infrastructure in dependency order
// Deploy with: az deployment group create --resource-group <rg> --template-file main.bicep --parameters parameters.dev.json

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('Environment name (dev, prod)')
@allowed(['dev', 'prod'])
param environment string

@description('Resource suffix (e.g., as01, 001)')
param suffix string

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Admin credentials for databases')
@secure()
param postgresAdminPassword string

@secure()
param mysqlAdminPassword string

@secure()
param sqlAdminPassword string

@secure()
param rabbitmqPassword string

@description('JWT configuration')
@secure()
param jwtSecret string
param jwtAlgorithm string = 'HS256'
param jwtIssuer string = 'auth-service'
param jwtAudience string = 'xshopai-platform'
param jwtExpiresIn string = '24h'

@description('Service tokens for inter-service auth')
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

@description('Azure AD Object ID of user/service principal to grant Key Vault access (optional)')
param keyVaultAdminObjectId string = ''

@description('Database usernames')
param postgresAdminUser string = 'pgadmin'
param mysqlAdminUser string = 'mysqladmin'
param sqlAdminUser string = 'sqladmin'
param rabbitmqUser string = 'admin'

// =============================================================================
// Variables
// =============================================================================

var resourcePrefix = 'xshopai-${suffix}'
var nodeEnv = environment == 'prod' ? 'production' : 'development'
var aspnetEnv = environment == 'prod' ? 'Production' : 'Development'

var tags = {
  project: 'xshopai'
  environment: environment
  suffix: suffix
  managedBy: 'bicep'
}

// =============================================================================
// Module Deployments (in dependency order)
// =============================================================================

// 1. Monitoring Foundation (no dependencies)
module monitoring './modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

// 2. App Service Plan (P3V3 Premium - production grade for all environments)
module appServicePlan './modules/app-service-plan.bicep' = {
  name: 'deploy-app-service-plan'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    sku: 'P3V3' // Explicitly set - do not change without team approval
  }
}

// 3. Data & Messaging Services (no dependencies, deploy in parallel)
module redis './modules/redis.bicep' = {
  name: 'deploy-redis'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

module cosmos './modules/cosmos.bicep' = {
  name: 'deploy-cosmos'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

module postgresql './modules/postgresql.bicep' = {
  name: 'deploy-postgresql'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    adminUser: postgresAdminUser
    adminPassword: postgresAdminPassword
    tags: tags
  }
}

module mysql './modules/mysql.bicep' = {
  name: 'deploy-mysql'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    adminUser: mysqlAdminUser
    adminPassword: mysqlAdminPassword
    tags: tags
  }
}

module sqlServer './modules/sql-server.bicep' = {
  name: 'deploy-sql-server'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    adminUser: sqlAdminUser
    adminPassword: sqlAdminPassword
    tags: tags
  }
}

module rabbitmq './modules/rabbitmq.bicep' = {
  name: 'deploy-rabbitmq'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    rabbitmqUser: rabbitmqUser
    rabbitmqPassword: rabbitmqPassword
    tags: tags
  }
}

module mailpit './modules/mailpit.bicep' = {
  name: 'deploy-mailpit'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

// 4. Azure OpenAI (no dependencies)
module openai './modules/openai.bicep' = {
  name: 'deploy-openai'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

// 5. Playwright Workspaces — Azure App Testing (no dependencies)
module playwright './modules/playwright.bicep' = {
  name: 'deploy-playwright'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

// 6. Key Vault (depends on monitoring for diagnostics)
module keyvault './modules/keyvault.bicep' = {
  name: 'deploy-keyvault'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    tags: tags
    // Secrets
    jwtSecret: jwtSecret
    jwtAlgorithm: jwtAlgorithm
    jwtIssuer: jwtIssuer
    jwtAudience: jwtAudience
    jwtExpiresIn: jwtExpiresIn
    // Database credentials
    postgresAdminUser: postgresAdminUser
    postgresAdminPassword: postgresAdminPassword
    mysqlAdminUser: mysqlAdminUser
    mysqlAdminPassword: mysqlAdminPassword
    sqlAdminUser: sqlAdminUser
    sqlAdminPassword: sqlAdminPassword
    // RabbitMQ
    rabbitmqUser: rabbitmqUser
    rabbitmqPassword: rabbitmqPassword
    rabbitmqHost: rabbitmq.outputs.rabbitmqHost
    // Redis
    redisHost: redis.outputs.redisHost
    redisKey: redis.outputs.redisPrimaryKey
    // Monitoring
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsKey: monitoring.outputs.appInsightsInstrumentationKey
    // Databases
    postgresHost: postgresql.outputs.postgresHost
    mysqlHost: mysql.outputs.mysqlHost
    sqlHost: sqlServer.outputs.sqlHost
    cosmosConnectionString: cosmos.outputs.cosmosConnectionString
    // Service tokens
    adminServiceToken: adminServiceToken
    authServiceToken: authServiceToken
    userServiceToken: userServiceToken
    cartServiceToken: cartServiceToken
    orderServiceToken: orderServiceToken
    productServiceToken: productServiceToken
    webBffToken: webBffToken
    // Azure OpenAI
    openaiEndpoint: openai.outputs.openaiEndpoint
    openaiDeployment: openai.outputs.deploymentName
    // SMTP (Mailpit)
    smtpHost: mailpit.outputs.smtpHost
    smtpPort: string(mailpit.outputs.smtpPort)
    // RBAC
    keyVaultAdminObjectId: keyVaultAdminObjectId
  }
}

// 6. App Services (depends on everything)
module appServices './modules/app-services.bicep' = {
  name: 'deploy-app-services'
  params: {
    location: location
    environment: environment
    resourcePrefix: resourcePrefix
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    // Monitoring
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsKey: monitoring.outputs.appInsightsInstrumentationKey
    // Environment configs
    nodeEnv: nodeEnv
    aspnetEnv: aspnetEnv
    // JWT & Auth
    jwtSecret: jwtSecret
    jwtAlgorithm: jwtAlgorithm
    jwtIssuer: jwtIssuer
    jwtAudience: jwtAudience
    jwtExpiresIn: jwtExpiresIn
    // RabbitMQ
    rabbitmqHost: rabbitmq.outputs.rabbitmqHost
    rabbitmqUser: rabbitmqUser
    rabbitmqPassword: rabbitmqPassword
    // Redis
    redisHost: redis.outputs.redisHost
    keyVaultName: keyvault.outputs.keyVaultName
    // Databases
    postgresHost: postgresql.outputs.postgresHost
    postgresAdminUser: postgresAdminUser
    postgresAdminPassword: postgresAdminPassword
    mysqlConnectionString: mysql.outputs.mysqlConnectionString
    sqlOrderConnectionString: sqlServer.outputs.orderDbConnectionString
    sqlPaymentConnectionString: sqlServer.outputs.paymentDbConnectionString
    cosmosConnectionString: cosmos.outputs.cosmosConnectionString
    // Azure OpenAI
    openaiEndpoint: openai.outputs.openaiEndpoint
    openaiDeployment: openai.outputs.deploymentName
    openaiResourceId: openai.outputs.openaiResourceId
    // SMTP (Mailpit)
    smtpHost: mailpit.outputs.smtpHost
    smtpPort: string(mailpit.outputs.smtpPort)
    // Service tokens
    adminServiceToken: adminServiceToken
    authServiceToken: authServiceToken
    userServiceToken: userServiceToken
    cartServiceToken: cartServiceToken
    orderServiceToken: orderServiceToken
    productServiceToken: productServiceToken
    webBffToken: webBffToken
    // Diagnostics
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

// =============================================================================
// Outputs
// =============================================================================

output resourceGroupName string = resourceGroup().name
output resourceGroupLocation string = location
output environment string = environment
output suffix string = suffix

// Monitoring
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output appInsightsName string = monitoring.outputs.appInsightsName
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString

// Compute
output appServicePlanId string = appServicePlan.outputs.appServicePlanId
output appServicePlanName string = appServicePlan.outputs.appServicePlanName

// App Services
output appServiceUrls object = appServices.outputs.serviceUrls

// Databases
output postgresHost string = postgresql.outputs.postgresHost
output mysqlHost string = mysql.outputs.mysqlHost
output sqlHost string = sqlServer.outputs.sqlHost
output cosmosAccountName string = cosmos.outputs.cosmosAccountName

// Messaging & Cache
output redisHost string = redis.outputs.redisHost
output rabbitmqHost string = rabbitmq.outputs.rabbitmqHost
output mailpitHost string = mailpit.outputs.smtpHost
output mailpitWebUrl string = mailpit.outputs.webUiUrl

// AI Services
output openaiEndpoint string = openai.outputs.openaiEndpoint
output openaiDeployment string = openai.outputs.deploymentName

// Key Vault
output keyVaultName string = keyvault.outputs.keyVaultName

// Playwright Workspaces (Azure App Testing)
output playwrightWorkspaceName string = playwright.outputs.playwrightWorkspaceName
output playwrightServiceUrl string = playwright.outputs.playwrightServiceUrl
output playwrightWorkspaceId string = playwright.outputs.playwrightWorkspaceId
output playwrightStorageAccountName string = playwright.outputs.storageAccountName
