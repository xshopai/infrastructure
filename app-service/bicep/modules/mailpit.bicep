// =============================================================================
// Mailpit - Azure Container Instance (SMTP Testing Server)
// =============================================================================
// Mailpit provides a local SMTP server for testing email functionality.
// - SMTP server on port 1025 (no authentication required)
// - Web UI on port 8025 for viewing captured emails
// - REST API for automated testing
//
// NOTE: This is for dev/test environments only. For production, use:
// - Azure Communication Services Email
// - SendGrid
// - Or another production email provider
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

@description('CPU cores')
param cpuCores int = 1

@description('Memory in GB')
param memoryGB int = 1

// =============================================================================
// Variables
// =============================================================================

var containerInstanceName = 'aci-mailpit-${replace(resourcePrefix, 'xshopai-', '')}'
var dnsLabel = containerInstanceName

// =============================================================================
// Resources
// =============================================================================

resource mailpitContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerInstanceName
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      dnsNameLabel: dnsLabel
      ports: [
        {
          protocol: 'TCP'
          port: 1025  // SMTP
        }
        {
          protocol: 'TCP'
          port: 8025  // Web UI
        }
      ]
    }
    containers: [
      {
        name: 'mailpit'
        properties: {
          // Use ghcr.io to avoid Docker Hub rate limits
          image: 'ghcr.io/axllent/mailpit:latest'
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryGB
            }
          }
          ports: [
            {
              protocol: 'TCP'
              port: 1025
            }
            {
              protocol: 'TCP'
              port: 8025
            }
          ]
          environmentVariables: [
            {
              name: 'MP_SMTP_BIND_ADDR'
              value: '0.0.0.0:1025'
            }
            {
              name: 'MP_UI_BIND_ADDR'
              value: '0.0.0.0:8025'
            }
            {
              name: 'MP_MAX_MESSAGES'
              value: '500'
            }
            {
              name: 'TZ'
              value: 'UTC'
            }
          ]
        }
      }
    ]
  }
}

// =============================================================================
// Outputs
// =============================================================================

output containerInstanceId string = mailpitContainer.id
output containerInstanceName string = mailpitContainer.name
output mailpitHost string = mailpitContainer.properties.ipAddress.fqdn
output mailpitIp string = mailpitContainer.properties.ipAddress.ip
output smtpHost string = mailpitContainer.properties.ipAddress.fqdn
output smtpPort int = 1025
output webUiUrl string = 'http://${mailpitContainer.properties.ipAddress.fqdn}:8025'
