// Admin UI - Administrative web application
// Database: None (static React app, calls admin-service)
// Runtime: Node.js (nginx serves static files)

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Short environment name (dev/pro)')
param shortEnv string

@description('App Service Plan ID')
param appServicePlanId string

@description('ACR login server URL')
param acrLoginServer string

@description('Application Insights instrumentation key')
param applicationInsightsKey string

@description('Resource tags')
param tags object

// Service-specific configuration
var serviceName = 'admin-ui'
var port = 3001

resource adminUi 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${serviceName}-${shortEnv}'
  location: location
  tags: union(tags, { Service: serviceName, Database: 'none' })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/${serviceName}:latest'
      alwaysOn: environment == 'production'
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        // Common settings
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'false' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${acrLoginServer}' }
        { name: 'DOCKER_ENABLE_CI', value: 'true' }
        { name: 'ENVIRONMENT', value: environment }
        { name: 'PORT', value: string(port) }
        { name: 'SERVICE_NAME', value: serviceName }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: 'InstrumentationKey=${applicationInsightsKey}' }
        
        // React app configuration (injected at build or runtime)
        { name: 'REACT_APP_ADMIN_SERVICE_URL', value: 'https://app-admin-service-${shortEnv}.azurewebsites.net' }
        { name: 'REACT_APP_AUTH_SERVICE_URL', value: 'https://app-auth-service-${shortEnv}.azurewebsites.net' }
        { name: 'REACT_APP_ENVIRONMENT', value: environment }
      ]
    }
  }
}

output appServiceName string = adminUi.name
output appServiceUrl string = 'https://${adminUi.properties.defaultHostName}'
output principalId string = adminUi.identity.principalId
