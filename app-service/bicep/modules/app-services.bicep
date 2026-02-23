// =============================================================================
// App Services - All 16 microservices with managed identities & configurations
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Environment name (dev, prod)')
param environment string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('App Service Plan resource ID')
param appServicePlanId string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Application Insights instrumentation key')
@secure()
param appInsightsKey string

@description('Node environment')
param nodeEnv string

@description('ASP.NET environment')
param aspnetEnv string

// JWT and Auth
@secure()
param jwtSecret string
param jwtAlgorithm string
param jwtIssuer string
param jwtAudience string
param jwtExpiresIn string

// RabbitMQ
param rabbitmqHost string
param rabbitmqUser string
@secure()
param rabbitmqPassword string

// Redis
param redisHost string
@secure()
param redisKey string

// PostgreSQL
param postgresHost string
param postgresAdminUser string
@secure()
param postgresAdminPassword string

// MySQL
@secure()
param mysqlConnectionString string

// SQL Server
@secure()
param sqlOrderConnectionString string
@secure()
param sqlPaymentConnectionString string

// Cosmos DB
@secure()
param cosmosConnectionString string

// Azure OpenAI
param openaiEndpoint string
param openaiDeployment string
param openaiResourceId string

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

// Diagnostics
param logAnalyticsWorkspaceId string

@description('Resource tags')
param tags object

// =============================================================================
// Variables
// =============================================================================

var suffix = split(resourcePrefix, '-')[1]

// Service definitions: name, runtime, health path
// Note: No startup commands - Azure will show default shell page until code is deployed
// Azure auto-detects startup from package.json, requirements.txt, etc. when code is deployed
var services = [
  { name: 'admin-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'admin-ui', runtime: 'NODE|24-lts', health: '/health' }
  { name: 'audit-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'auth-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'cart-service', runtime: 'JAVA|17-java17', health: '/health/live' }
  { name: 'chat-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'customer-ui', runtime: 'NODE|24-lts', health: '/health' }
  { name: 'inventory-service', runtime: 'PYTHON|3.11', health: '/health/live' }
  { name: 'notification-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'order-processor-service', runtime: 'JAVA|17-java17', health: '/health/live' }
  { name: 'order-service', runtime: 'DOTNETCORE|8.0', health: '/health/live' }
  { name: 'payment-service', runtime: 'DOTNETCORE|8.0', health: '/health/live' }
  { name: 'product-service', runtime: 'PYTHON|3.11', health: '/health/live' }
  { name: 'review-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'user-service', runtime: 'NODE|24-lts', health: '/health/live' }
  { name: 'web-bff', runtime: 'NODE|24-lts', health: '/health/live' }
]

// Helper function for service URLs
var serviceUrlPrefix = 'https://app-'
var serviceUrlSuffix = '-xshopai-${suffix}.azurewebsites.net'

// Build RabbitMQ URL
var rabbitmqUrl = 'amqp://${rabbitmqUser}:${rabbitmqPassword}@${rabbitmqHost}:5672'

// Build MongoDB URIs
var userMongodbUri = '${cosmosConnectionString}user_service_db?retryWrites=true&w=majority'
var productMongodbUri = '${cosmosConnectionString}product_service_db?retryWrites=true&w=majority'
var reviewMongodbUri = '${cosmosConnectionString}review_service_db?retryWrites=true&w=majority'

// =============================================================================
// App Services
// =============================================================================

// Create all 16 App Services
resource appServices 'Microsoft.Web/sites@2022-09-01' = [for svc in services: {
  name: 'app-${svc.name}-xshopai-${suffix}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: svc.runtime
      // appCommandLine not set - allows Azure to show default shell page until code deployed
      alwaysOn: true
      healthCheckPath: svc.health
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      scmIpSecurityRestrictionsUseMain: true
      appSettings: [] // Will be set per service below
    }
  }
}]

// =============================================================================
// Service-specific configurations (app settings)
// =============================================================================

// 1. admin-service
resource adminServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[0]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'admin-service'
    VERSION: '1.0.0'
    SERVICE_INVOCATION_MODE: 'http'
    JWT_SECRET: jwtSecret
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    MESSAGING_PROVIDER: 'rabbitmq'
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'admin-service'
    LOG_LEVEL: 'info'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
    AUTH_SERVICE_URL: '${serviceUrlPrefix}auth-service${serviceUrlSuffix}'
    USER_SERVICE_URL: '${serviceUrlPrefix}user-service${serviceUrlSuffix}'
    PRODUCT_SERVICE_URL: '${serviceUrlPrefix}product-service${serviceUrlSuffix}'
    ORDER_SERVICE_URL: '${serviceUrlPrefix}order-service${serviceUrlSuffix}'
    PAYMENT_SERVICE_URL: '${serviceUrlPrefix}payment-service${serviceUrlSuffix}'
    AUDIT_SERVICE_URL: '${serviceUrlPrefix}audit-service${serviceUrlSuffix}'
    NOTIFICATION_SERVICE_URL: '${serviceUrlPrefix}notification-service${serviceUrlSuffix}'
    USER_SERVICE_TOKEN: userServiceToken
  }
}

// 2. admin-ui
resource adminUiConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[1]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    BFF_URL: '${serviceUrlPrefix}web-bff${serviceUrlSuffix}'
  }
}

// Note: startup command will be set during deployment, not during infra provisioning

// 3. audit-service
resource auditServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[2]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'audit-service'
    VERSION: '1.0.0'
    POSTGRES_HOST: postgresHost
    POSTGRES_PORT: '5432'
    POSTGRES_DB: 'audit_service_db'
    POSTGRES_USER: postgresAdminUser
    POSTGRES_PASSWORD: postgresAdminPassword
    DB_SSL: 'true'
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'audit-service'
  }
}

// 4. auth-service
resource authServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[3]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'auth-service'
    VERSION: '1.0.0'
    JWT_SECRET: jwtSecret
    JWT_ALGORITHM: jwtAlgorithm
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    JWT_EXPIRES_IN: jwtExpiresIn
    USER_SERVICE_URL: '${serviceUrlPrefix}user-service${serviceUrlSuffix}'
    USER_SERVICE_TOKEN: userServiceToken
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'auth-service'
    LOG_LEVEL: 'info'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// 5. cart-service
resource cartServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[4]
  name: 'appsettings'
  properties: {
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
    QUARKUS_HTTP_PORT: '8080'
    REDIS_HOST: redisHost
    REDIS_PORT: '6380'
    REDIS_PASSWORD: redisKey
    RABBITMQ_HOST: rabbitmqHost
    RABBITMQ_PORT: '5672'
    RABBITMQ_USERNAME: rabbitmqUser
    RABBITMQ_PASSWORD: rabbitmqPassword
    RABBITMQ_EXCHANGE: 'xshopai.events'
    JWT_SECRET: jwtSecret
    SERVICE_TOKEN: cartServiceToken
    SERVICE_TOKEN_ENABLED: 'true'
    PRODUCT_SERVICE_URL: '${serviceUrlPrefix}product-service${serviceUrlSuffix}'
    INVENTORY_SERVICE_URL: '${serviceUrlPrefix}inventory-service${serviceUrlSuffix}'
    QUARKUS_OTEL_ENABLED: 'false'
    OTEL_SERVICE_NAME: 'cart-service'
  }
}

// 6. chat-service
resource chatServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[5]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'chat-service'
    VERSION: '1.0.0'
    SERVICE_INVOCATION_MODE: 'http'
    PRODUCT_SERVICE_URL: '${serviceUrlPrefix}product-service${serviceUrlSuffix}'
    ORDER_SERVICE_URL: '${serviceUrlPrefix}order-service${serviceUrlSuffix}'
    AZURE_OPENAI_ENDPOINT: openaiEndpoint
    AZURE_OPENAI_DEPLOYMENT_NAME: openaiDeployment
    AZURE_OPENAI_API_VERSION: '2024-10-21'
    AZURE_USE_MANAGED_IDENTITY: 'true'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'chat-service'
    LOG_LEVEL: 'info'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
    WEBSITE_RUN_FROM_PACKAGE: '1'
  }
}

// Set chat-service startup command
resource chatServiceStartup 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[5]
  name: 'web'
  properties: {
    appCommandLine: 'node dist/src/server.js'
  }
  dependsOn: [
    chatServiceConfig
  ]
}

// Grant chat-service Managed Identity access to Azure OpenAI
resource chatServiceOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appServices[5].id, openaiResourceId, 'CognitiveServicesOpenAIUser')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: appServices[5].identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// 7. customer-ui
resource customerUiConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[6]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    BFF_URL: '${serviceUrlPrefix}web-bff${serviceUrlSuffix}'
  }
}

// Note: startup command will be set during deployment, not during infra provisioning

// 8. inventory-service
resource inventoryServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[7]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    FLASK_APP: 'run.py'
    MYSQL_SERVER_CONNECTION: mysqlConnectionString
    DB_NAME: 'inventory_service_db'
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    JWT_SECRET: jwtSecret
    JWT_ALGORITHM: jwtAlgorithm
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    PRODUCT_SERVICE_URL: '${serviceUrlPrefix}product-service${serviceUrlSuffix}'
    PRODUCT_SERVICE_TOKEN: productServiceToken
    ORDER_SERVICE_TOKEN: orderServiceToken
    CART_SERVICE_TOKEN: cartServiceToken
    WEBBFF_SERVICE_TOKEN: webBffToken
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'inventory-service'
    LOG_LEVEL: 'INFO'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// Note: startup command will be set during deployment via Oryx build detection

// 9. notification-service
resource notificationServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[8]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    SMTP_HOST: ''
    SMTP_PORT: '587'
    SMTP_USER: ''
    SMTP_PASS: ''
    SMTP_SECURE: 'false'
    EMAIL_FROM_ADDRESS: 'noreply@xshopai.com'
    EMAIL_FROM_NAME: 'xShopAI'
    EMAIL_ENABLED: 'false'
    EMAIL_PROVIDER: 'smtp'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'notification-service'
  }
}

// 10. order-processor-service
resource orderProcessorServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[9]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
    SERVER_PORT: '8080'
    SPRING_DATASOURCE_URL: 'jdbc:postgresql://${postgresHost}:5432/order_processor_db?sslmode=require'
    SPRING_DATASOURCE_USERNAME: postgresAdminUser
    SPRING_DATASOURCE_PASSWORD: postgresAdminPassword
    RABBITMQ_HOST: rabbitmqHost
    RABBITMQ_PORT: '5672'
    RABBITMQ_USERNAME: rabbitmqUser
    RABBITMQ_PASSWORD: rabbitmqPassword
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    MANAGEMENT_TRACING_ENABLED: 'false'
    OTEL_SERVICE_NAME: 'order-processor-service'
    LOG_LEVEL: 'INFO'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// 11. order-service
resource orderServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[10]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    ASPNETCORE_ENVIRONMENT: aspnetEnv
    ASPNETCORE_URLS: 'http://0.0.0.0:8080'
    DATABASE_CONNECTION_STRING: sqlOrderConnectionString
    RABBITMQ_CONNECTION_STRING: rabbitmqUrl
    RabbitMQ__ExchangeName: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    Jwt__Secret: jwtSecret
    Jwt__Issuer: jwtIssuer
    Jwt__Audience: jwtAudience
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'order-service'
  }
}

// 12. payment-service
resource paymentServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[11]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    ASPNETCORE_ENVIRONMENT: aspnetEnv
    ASPNETCORE_URLS: 'http://0.0.0.0:8080'
    ConnectionStrings__DefaultConnection: sqlPaymentConnectionString
    RABBITMQ_CONNECTION_STRING: rabbitmqUrl
    RabbitMQ__ExchangeName: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    Jwt__Key: jwtSecret
    Jwt__Issuer: jwtIssuer
    Jwt__Audience: jwtAudience
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'payment-service'
  }
}

// 13. product-service
resource productServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[12]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NAME: 'product-service'
    API_VERSION: '1.0.0'
    MONGODB_URI: productMongodbUri
    MONGODB_DB_NAME: 'product_service_db'
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    JWT_SECRET: jwtSecret
    JWT_ALGORITHM: jwtAlgorithm
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'product-service'
    LOG_LEVEL: 'INFO'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// Note: startup command will be set during deployment via Oryx build detection

// 14. review-service
resource reviewServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[13]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'review-service'
    VERSION: '1.0.0'
    MONGODB_URI: reviewMongodbUri
    MONGODB_DB_NAME: 'review_service_db'
    JWT_SECRET: jwtSecret
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'review-service'
    LOG_LEVEL: 'info'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// 15. user-service
resource userServiceConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[14]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'user-service'
    VERSION: '1.0.0'
    MONGODB_URI: userMongodbUri
    MONGODB_DB_NAME: 'user_service_db'
    JWT_SECRET: jwtSecret
    JWT_ALGORITHM: jwtAlgorithm
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    JWT_EXPIRES_IN: jwtExpiresIn
    RABBITMQ_URL: rabbitmqUrl
    RABBITMQ_EXCHANGE: 'xshopai.events'
    MESSAGING_PROVIDER: 'rabbitmq'
    AUTH_SERVICE_TOKEN: authServiceToken
    ADMIN_SERVICE_TOKEN: adminServiceToken
    ORDER_SERVICE_TOKEN: orderServiceToken
    WEBBFF_SERVICE_TOKEN: webBffToken
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'user-service'
    LOG_LEVEL: 'INFO'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// 16. web-bff
resource webBffConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: appServices[15]
  name: 'appsettings'
  properties: {
    PORT: '8080'
    ENVIRONMENT: environment
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsKey
    NODE_ENV: nodeEnv
    SERVICE_NAME: 'web-bff'
    VERSION: '1.0.0'
    SERVICE_INVOCATION_MODE: 'http'
    MESSAGING_PROVIDER: 'rabbitmq'
    JWT_SECRET: jwtSecret
    JWT_ISSUER: jwtIssuer
    JWT_AUDIENCE: jwtAudience
    ALLOWED_ORIGINS: '${serviceUrlPrefix}customer-ui${serviceUrlSuffix}'
    AUTH_SERVICE_URL: '${serviceUrlPrefix}auth-service${serviceUrlSuffix}'
    USER_SERVICE_URL: '${serviceUrlPrefix}user-service${serviceUrlSuffix}'
    PRODUCT_SERVICE_URL: '${serviceUrlPrefix}product-service${serviceUrlSuffix}'
    CART_SERVICE_URL: '${serviceUrlPrefix}cart-service${serviceUrlSuffix}'
    ORDER_SERVICE_URL: '${serviceUrlPrefix}order-service${serviceUrlSuffix}'
    PAYMENT_SERVICE_URL: '${serviceUrlPrefix}payment-service${serviceUrlSuffix}'
    REVIEW_SERVICE_URL: '${serviceUrlPrefix}review-service${serviceUrlSuffix}'
    INVENTORY_SERVICE_URL: '${serviceUrlPrefix}inventory-service${serviceUrlSuffix}'
    ADMIN_SERVICE_URL: '${serviceUrlPrefix}admin-service${serviceUrlSuffix}'
    CHAT_SERVICE_URL: '${serviceUrlPrefix}chat-service${serviceUrlSuffix}'
    OTEL_TRACES_EXPORTER: 'azure'
    OTEL_SERVICE_NAME: 'web-bff'
    LOG_LEVEL: 'info'
    LOG_FORMAT: 'json'
    LOG_TO_CONSOLE: 'true'
  }
}

// =============================================================================
// Diagnostic Settings (all services → Log Analytics)
// =============================================================================

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [for (svc, i) in services: {
  name: 'diag-app-${svc.name}-xshopai-${environment}-${suffix}'
  scope: appServices[i]
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AppServiceHTTPLogs', enabled: true }
      { category: 'AppServiceConsoleLogs', enabled: true }
      { category: 'AppServiceAppLogs', enabled: true }
      { category: 'AppServicePlatformLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}]

// =============================================================================
// Outputs
// =============================================================================

output serviceUrls object = {
  adminService: appServices[0].properties.defaultHostName
  adminUi: appServices[1].properties.defaultHostName
  auditService: appServices[2].properties.defaultHostName
  authService: appServices[3].properties.defaultHostName
  cartService: appServices[4].properties.defaultHostName
  chatService: appServices[5].properties.defaultHostName
  customerUi: appServices[6].properties.defaultHostName
  inventoryService: appServices[7].properties.defaultHostName
  notificationService: appServices[8].properties.defaultHostName
  orderProcessorService: appServices[9].properties.defaultHostName
  orderService: appServices[10].properties.defaultHostName
  paymentService: appServices[11].properties.defaultHostName
  productService: appServices[12].properties.defaultHostName
  reviewService: appServices[13].properties.defaultHostName
  userService: appServices[14].properties.defaultHostName
  webBff: appServices[15].properties.defaultHostName
}

output appServiceIds array = [for (svc, i) in services: appServices[i].id]
output appServiceNames array = [for (svc, i) in services: appServices[i].name]
