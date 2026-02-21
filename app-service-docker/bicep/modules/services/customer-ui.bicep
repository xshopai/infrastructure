// Customer UI - Customer-facing web application
// Database: None (static React app, calls BFF)
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
var serviceName = 'customer-ui'
var port = 3000

resource customerUi 'Microsoft.Web/sites@2023-01-01' = {
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
        { name: 'REACT_APP_BFF_URL', value: 'https://app-web-bff-${shortEnv}.azurewebsites.net' }
        { name: 'REACT_APP_ENVIRONMENT', value: environment }
        { name: 'REACT_APP_CHAT_URL', value: 'wss://app-chat-service-${shortEnv}.azurewebsites.net/ws' }
      ]
    }
  }
}

output appServiceName string = customerUi.name
output appServiceUrl string = 'https://${customerUi.properties.defaultHostName}'
output principalId string = customerUi.identity.principalId
