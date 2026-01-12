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

// Web BFF - Backend for Frontend (API aggregation layer for customer-ui)
resource webBff 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'web-bff'
  location: location
  tags: union(tags, {
    service: 'web-bff'
    type: 'backend'
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
            'PATCH'
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
        enabled: true
        appId: 'web-bff'
        appPort: 8080
        appProtocol: 'http'
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
          name: 'web-bff'
          image: placeholderImage  // Placeholder - CI/CD will update
          resources: {
            cpu: json(environment == 'prod' ? '1' : '0.5')
            memory: environment == 'prod' ? '2Gi' : '1Gi'
          }
          env: [
            {
              name: 'NODE_ENV'
              value: 'production'
            }
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'HOST'
              value: '0.0.0.0'
            }
            {
              name: 'LOG_LEVEL'
              value: environment == 'prod' ? 'warn' : 'info'
            }
            {
              name: 'PRODUCT_SERVICE_APP_ID'
              value: 'product-service'
            }
            {
              name: 'INVENTORY_SERVICE_APP_ID'
              value: 'inventory-service'
            }
            {
              name: 'REVIEW_SERVICE_APP_ID'
              value: 'review-service'
            }
            {
              name: 'AUTH_SERVICE_APP_ID'
              value: 'auth-service'
            }
            {
              name: 'USER_SERVICE_APP_ID'
              value: 'user-service'
            }
            {
              name: 'CART_SERVICE_APP_ID'
              value: 'cart-service'
            }
            {
              name: 'ORDER_SERVICE_APP_ID'
              value: 'order-service'
            }
            {
              name: 'ADMIN_SERVICE_APP_ID'
              value: 'admin-service'
            }
            {
              name: 'CHAT_SERVICE_APP_ID'
              value: 'chat-service'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1  // Always have at least 1 replica for health probes
        maxReplicas: environment == 'prod' ? 10 : 5
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// Product Service - Python/FastAPI backend for product catalog management
resource productService 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'product-service'
  location: location
  tags: union(tags, {
    service: 'product-service'
    type: 'backend'
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
        external: false  // Internal only - accessed via Dapr service invocation
        targetPort: 1001
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      dapr: {
        enabled: true
        appId: 'product-service'
        appPort: 1001
        appProtocol: 'http'
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
          name: 'product-service'
          image: placeholderImage  // Placeholder - CI/CD will update
          resources: {
            cpu: json(environment == 'prod' ? '1' : '0.5')
            memory: environment == 'prod' ? '2Gi' : '1Gi'
          }
          env: [
            {
              name: 'ENVIRONMENT'
              value: 'production'
            }
            {
              name: 'DEBUG'
              value: 'false'
            }
            {
              name: 'NAME'
              value: 'product-service'
            }
            {
              name: 'VERSION'
              value: '1.0.0'
            }
            {
              name: 'PORT'
              value: '1001'
            }
            {
              name: 'LOG_LEVEL'
              value: environment == 'prod' ? 'WARNING' : 'INFO'
            }
            {
              name: 'LOG_FORMAT'
              value: 'json'
            }
            {
              name: 'LOG_TO_CONSOLE'
              value: 'true'
            }
            {
              name: 'LOG_TO_FILE'
              value: 'false'
            }
            {
              name: 'DAPR_HOST'
              value: 'localhost'
            }
            {
              name: 'DAPR_HTTP_PORT'
              value: '3500'
            }
            {
              name: 'DAPR_GRPC_PORT'
              value: '50001'
            }
            {
              name: 'DAPR_APP_ID'
              value: 'product-service'
            }
            {
              name: 'DAPR_PUBSUB_NAME'
              value: 'event-bus'
            }
            {
              name: 'DAPR_INVENTORY_SERVICE_APP_ID'
              value: 'inventory-service'
            }
            {
              name: 'WORKERS'
              value: environment == 'prod' ? '4' : '2'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 1001
                scheme: 'HTTP'
              }
              initialDelaySeconds: 15
              periodSeconds: 30
              failureThreshold: 3
              timeoutSeconds: 5
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/readiness'
                port: 1001
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
              timeoutSeconds: 5
            }
            {
              type: 'Startup'
              httpGet: {
                path: '/readiness'
                port: 1001
                scheme: 'HTTP'
              }
              initialDelaySeconds: 0
              periodSeconds: 10
              failureThreshold: 30
              timeoutSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1  // Always have at least 1 replica for health probes
        maxReplicas: environment == 'prod' ? 10 : 5
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

@description('Web BFF Container App URL')
output webBffUrl string = 'https://${webBff.properties.configuration.ingress.fqdn}'

@description('Web BFF Container App FQDN')
output webBffFqdn string = webBff.properties.configuration.ingress.fqdn

@description('Web BFF Container App Resource ID')
output webBffId string = webBff.id

@description('Web BFF Container App Name')
output webBffName string = webBff.name

@description('Product Service Container App FQDN')
output productServiceFqdn string = productService.properties.configuration.ingress.fqdn

@description('Product Service Container App Resource ID')
output productServiceId string = productService.id

@description('Product Service Container App Name')
output productServiceName string = productService.name
