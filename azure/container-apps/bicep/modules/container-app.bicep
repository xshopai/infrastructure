// ============================================================================
// Container App Module
// ============================================================================
// Reusable module for deploying Azure Container Apps
// Supports: HTTP services, background workers, Dapr sidecars
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Name of the Container App')
param name string

@description('Azure region for deployment. Default: Sweden Central')
param location string = 'swedencentral'

@description('Resource ID of the Container Apps Environment')
param environmentId string

@description('Container image to deploy (e.g., myregistry.azurecr.io/myapp:latest)')
param containerImage string

@description('Container registry server (e.g., myregistry.azurecr.io)')
param containerRegistryServer string = ''

@description('Container registry username')
@secure()
param containerRegistryUsername string = ''

@description('Container registry password')
@secure()
param containerRegistryPassword string = ''

@description('CPU cores allocated to the container (e.g., 0.25, 0.5, 1, 2)')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1'
  '1.25'
  '1.5'
  '1.75'
  '2'
])
param cpu string = '0.5'

@description('Memory allocated to the container (e.g., 0.5Gi, 1Gi, 2Gi)')
@allowed([
  '0.5Gi'
  '1Gi'
  '1.5Gi'
  '2Gi'
  '2.5Gi'
  '3Gi'
  '3.5Gi'
  '4Gi'
])
param memory string = '1Gi'

@description('Port the container listens on')
param targetPort int = 8080

@description('Enable external ingress (accessible from internet)')
param externalIngress bool = true

@description('Minimum number of replicas')
@minValue(0)
@maxValue(30)
param minReplicas int = 0

@description('Maximum number of replicas')
@minValue(1)
@maxValue(30)
param maxReplicas int = 10

@description('Environment variables for the container')
param envVars array = []

@description('Secret references for the container')
@secure()
param secrets array = []

@description('Enable Dapr sidecar')
param daprEnabled bool = false

@description('Dapr application ID')
param daprAppId string = ''

@description('Dapr application port')
param daprAppPort int = 0

@description('Dapr application protocol (http or grpc)')
@allowed([
  'http'
  'grpc'
])
param daprAppProtocol string = 'http'

@description('Custom health probe path')
param healthProbePath string = '/health'

@description('Tags to apply to the resource')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var hasRegistryCredentials = !empty(containerRegistryUsername) && !empty(containerRegistryPassword)

var registrySecrets = hasRegistryCredentials ? [
  {
    name: 'registry-password'
    value: containerRegistryPassword
  }
] : []

var allSecrets = concat(registrySecrets, secrets)

var registries = hasRegistryCredentials ? [
  {
    server: containerRegistryServer
    username: containerRegistryUsername
    passwordSecretRef: 'registry-password'
  }
] : []

// ============================================================================
// Resources
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  properties: {
    environmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: externalIngress || targetPort > 0 ? {
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      } : null
      secrets: allSecrets
      registries: registries
      dapr: daprEnabled ? {
        enabled: true
        appId: daprAppId
        appPort: daprAppPort > 0 ? daprAppPort : targetPort
        appProtocol: daprAppProtocol
      } : null
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
                path: healthProbePath
                port: targetPort
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: healthProbePath
                port: targetPort
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
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
  tags: union(tags, {
    'managed-by': 'bicep'
    'deployment-target': 'container-apps'
  })
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the Container App')
output name string = containerApp.name

@description('The FQDN of the Container App')
output fqdn string = containerApp.properties.configuration.ingress != null ? containerApp.properties.configuration.ingress.fqdn : ''

@description('The URL of the Container App')
output url string = containerApp.properties.configuration.ingress != null ? 'https://${containerApp.properties.configuration.ingress.fqdn}' : ''

@description('The resource ID of the Container App')
output resourceId string = containerApp.id

@description('The latest revision name')
output latestRevisionName string = containerApp.properties.latestRevisionName
