// ============================================================================
// Reusable Container App Module
// Version: 1.0.0
// Description: Generic Container App deployment for xshopai microservices
// ============================================================================

@description('Name of the Container App')
param containerAppName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Tags to apply to resources')
param tags object = {}

@description('Container Apps Environment resource ID')
param containerAppsEnvironmentId string

@description('Container image (e.g., ghcr.io/xshopai/inventory-service:latest)')
param containerImage string

@description('Container registry server (e.g., ghcr.io)')
param containerRegistry string = 'ghcr.io'

@description('Container registry username (optional for public registries)')
@secure()
param containerRegistryUsername string = ''

@description('Container registry password (optional for public registries)')
@secure()
param containerRegistryPassword string = ''

@description('Container port the app listens on')
param containerPort int = 8080

@description('External ingress enabled')
param externalIngress bool = true

@description('Target port for ingress')
param targetPort int = 8080

@description('Allow insecure traffic')
param allowInsecure bool = false

@description('CPU cores (e.g., 0.25, 0.5, 1.0)')
param cpu string = '0.5'

@description('Memory in Gi (e.g., 0.5Gi, 1.0Gi)')
param memory string = '1.0Gi'

@description('Minimum replicas')
param minReplicas int = 1

@description('Maximum replicas')
param maxReplicas int = 10

@description('Environment variables for the container')
param environmentVariables array = []

@description('Secrets to inject into the container')
@secure()
param secrets array = []

@description('Dapr configuration')
param dapr object = {
  enabled: true
  appId: containerAppName
  appPort: containerPort
  appProtocol: 'http'
  enableApiLogging: true
}

@description('Managed Identity configuration')
param identity object = {
  type: 'SystemAssigned'
}

// ============================================================================
// Container App Resource
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: identity
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: allowInsecure
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: !empty(containerRegistryUsername) ? [
        {
          server: containerRegistry
          username: containerRegistryUsername
          passwordSecretRef: 'container-registry-password'
        }
      ] : []
      secrets: concat(
        !empty(containerRegistryPassword) ? [
          {
            name: 'container-registry-password'
            value: containerRegistryPassword
          }
        ] : [],
        secrets
      )
      dapr: dapr.enabled ? {
        enabled: true
        appId: dapr.appId
        appPort: dapr.appPort
        appProtocol: dapr.appProtocol
        enableApiLogging: dapr.?enableApiLogging ?? true
      } : {
        enabled: false
      }
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: environmentVariables
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
                concurrentRequests: '10'
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
output containerAppId string = containerApp.id

@description('Container App name')
output containerAppName string = containerApp.name

@description('Container App FQDN')
output fqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Container App latest revision name')
output latestRevisionName string = containerApp.properties.latestRevisionName

@description('Container App outbound IP addresses')
output outboundIpAddresses array = containerApp.properties.outboundIpAddresses

@description('System-assigned managed identity principal ID')
output identityPrincipalId string = containerApp.identity.principalId
