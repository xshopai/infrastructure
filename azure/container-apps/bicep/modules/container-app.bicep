// ============================================================================
// Container App Module
// ============================================================================
// Deploys a single Container App instance for a microservice
// Used by individual service CI/CD pipelines after infrastructure is provisioned
// ============================================================================

@description('Name of the Container App')
param name string

@description('Location for the Container App')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Container Apps Environment resource ID')
param containerAppsEnvironmentId string

@description('User-assigned Managed Identity resource ID')
param managedIdentityId string

@description('Container Registry login server (e.g., crxshopaidev.azurecr.io)')
param containerRegistryServer string

@description('Full container image with tag (e.g., crxshopaidev.azurecr.io/user-service:v1.0.0)')
param containerImage string

@description('Container port to expose')
param containerPort int = 3000

@description('Environment variables for the container')
param envVars array = []

@description('Secrets for the container (name/value pairs)')
@secure()
param secrets array = []

@description('Health check path')
param healthCheckPath string = '/health'

@description('Enable Dapr sidecar')
param daprEnabled bool = true

@description('Dapr app ID (defaults to container app name)')
param daprAppId string = ''

@description('Dapr app port (defaults to container port)')
param daprAppPort int = 0

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 3

@description('CPU allocation (e.g., 0.5, 1.0, 2.0)')
param cpu string = '0.5'

@description('Memory allocation (e.g., 1.0Gi, 2.0Gi)')
param memory string = '1.0Gi'

@description('Enable external ingress')
param externalIngress bool = true

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var effectiveDaprAppId = empty(daprAppId) ? name : daprAppId
var effectiveDaprAppPort = daprAppPort == 0 ? containerPort : daprAppPort

var defaultTags = {
  service: name
  environment: environment
  managedBy: 'bicep'
}

var allTags = union(defaultTags, tags)

// ============================================================================
// Container App
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  tags: allTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: externalIngress
        targetPort: containerPort
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
            'https://admin.xshopai.com'
          ] : [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'PATCH'
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
      dapr: daprEnabled ? {
        enabled: true
        appId: effectiveDaprAppId
        appPort: effectiveDaprAppPort
        appProtocol: 'http'
        enableApiLogging: environment != 'prod'
        logLevel: environment == 'prod' ? 'warn' : 'info'
      } : {
        enabled: false
      }
      secrets: secrets
      registries: [
        {
          server: containerRegistryServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: envVars
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: healthCheckPath
                port: containerPort
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
                path: healthCheckPath
                port: containerPort
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
                path: healthCheckPath
                port: containerPort
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
        minReplicas: minReplicas
        maxReplicas: maxReplicas
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

@description('Container App resource ID')
output id string = containerApp.id

@description('Container App name')
output appName string = containerApp.name

@description('Container App FQDN')
output fqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Container App URL')
output url string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Container App latest revision name')
output latestRevisionName string = containerApp.properties.latestRevisionName

@description('Dapr app ID')
output daprAppId string = effectiveDaprAppId
