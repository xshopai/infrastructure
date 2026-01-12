// ============================================================================
// xshopai Platform - Layer 4: Container Apps
// Creates: Container App instances for microservices
// Depends on: Layer 0 (Foundation), Layer 1 (Core Platform)
// ============================================================================
// This layer creates Container App "shells" with placeholder images.
// Application code is deployed separately via GitHub Actions workflows.
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Project name prefix for resource naming')
param projectName string = 'xshopai'

@description('Tags to apply to all resources')
param tags object = {
  project: projectName
  environment: environment
  managedBy: 'bicep'
  layer: 'container-apps'
}

@description('Container Apps Environment Name (from Layer 1)')
param containerAppsEnvName string

@description('Container Registry Login Server (from Layer 1)')
param acrLoginServer string

@description('Managed Identity Resource ID (from Layer 0)')
param managedIdentityId string

// ============================================================================
// Variables
// ============================================================================

var resourcePrefix = '${projectName}-${environment}'

// Placeholder image - will be replaced by CI/CD pipelines
// Using mcr.microsoft.com/k8se/quickstart as it's always available
var placeholderImage = 'mcr.microsoft.com/k8se/quickstart:latest'

// ============================================================================
// Existing Resources (from previous layers)
// ============================================================================

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: containerAppsEnvName
}

// ============================================================================
// Container Apps
// ============================================================================

// Customer UI - React SPA frontend
resource customerUi 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'customer-ui'
  location: location
  tags: union(tags, {
    service: 'customer-ui'
    type: 'frontend'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
        corsPolicy: {
          allowedOrigins: environment == 'prod' ? [
            'https://xshopai.com'
            'https://www.xshopai.com'
          ] : [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'DELETE'
            'OPTIONS'
          ]
          allowedHeaders: [
            '*'
          ]
          exposeHeaders: [
            '*'
          ]
          allowCredentials: true
          maxAge: 3600
        }
      }
      dapr: {
        enabled: false  // Customer UI doesn't use Dapr
      }
      registries: [
        {
          server: acrLoginServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'customer-ui'
          image: placeholderImage  // Placeholder - CI/CD will update
          resources: {
            cpu: json(environment == 'prod' ? '0.5' : '0.25')
            memory: environment == 'prod' ? '1Gi' : '0.5Gi'
          }
          env: [
            {
              name: 'REACT_APP_ENVIRONMENT'
              value: environment
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1  // Always have at least 1 replica for health probes
        maxReplicas: environment == 'prod' ? 10 : 3
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// Admin UI - React SPA admin dashboard
resource adminUi 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'admin-ui'
  location: location
  tags: union(tags, {
    service: 'admin-ui'
    type: 'frontend'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
        corsPolicy: {
          allowedOrigins: environment == 'prod' ? [
            'https://admin.xshopai.com'
          ] : [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'DELETE'
            'OPTIONS'
          ]
          allowedHeaders: [
            '*'
          ]
          exposeHeaders: [
            '*'
          ]
          allowCredentials: true
          maxAge: 3600
        }
      }
      dapr: {
        enabled: false  // Admin UI doesn't use Dapr
      }
      registries: [
        {
          server: acrLoginServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'admin-ui'
          image: placeholderImage  // Placeholder - CI/CD will update
          resources: {
            cpu: json(environment == 'prod' ? '0.5' : '0.25')
            memory: environment == 'prod' ? '1Gi' : '0.5Gi'
          }
          env: [
            {
              name: 'REACT_APP_ENVIRONMENT'
              value: environment
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1  // Always have at least 1 replica for health probes
        maxReplicas: environment == 'prod' ? 10 : 3
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Customer UI Container App URL')
output customerUiUrl string = 'https://${customerUi.properties.configuration.ingress.fqdn}'

@description('Customer UI Container App FQDN')
output customerUiFqdn string = customerUi.properties.configuration.ingress.fqdn

@description('Customer UI Container App Resource ID')
output customerUiId string = customerUi.id

@description('Customer UI Container App Name')
output customerUiName string = customerUi.name

@description('Admin UI Container App URL')
output adminUiUrl string = 'https://${adminUi.properties.configuration.ingress.fqdn}'

@description('Admin UI Container App FQDN')
output adminUiFqdn string = adminUi.properties.configuration.ingress.fqdn

@description('Admin UI Container App Resource ID')
output adminUiId string = adminUi.id

@description('Admin UI Container App Name')
output adminUiName string = adminUi.name
