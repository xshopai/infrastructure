// =============================================================================
// RabbitMQ - Azure Container Instance (3-management)
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('RabbitMQ username')
param rabbitmqUser string

@description('RabbitMQ password')
@secure()
param rabbitmqPassword string

@description('Resource tags')
param tags object

@description('CPU cores')
param cpuCores int = 1

@description('Memory in GB')
param memoryGB int = 2

// =============================================================================
// Variables
// =============================================================================

var containerInstanceName = 'aci-rabbitmq-${replace(resourcePrefix, 'xshopai-', '')}'
var dnsLabel = containerInstanceName

// =============================================================================
// Resources
// =============================================================================

resource rabbitmqContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
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
          port: 5672
        }
        {
          protocol: 'TCP'
          port: 15672
        }
      ]
    }
    containers: [
      {
        name: 'rabbitmq'
        properties: {
          image: 'mcr.microsoft.com/mirror/docker/library/rabbitmq:3-management'
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryGB
            }
          }
          ports: [
            {
              protocol: 'TCP'
              port: 5672
            }
            {
              protocol: 'TCP'
              port: 15672
            }
          ]
          environmentVariables: [
            {
              name: 'RABBITMQ_DEFAULT_USER'
              value: rabbitmqUser
            }
            {
              name: 'RABBITMQ_DEFAULT_PASS'
              secureValue: rabbitmqPassword
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

output containerInstanceId string = rabbitmqContainer.id
output containerInstanceName string = rabbitmqContainer.name
output rabbitmqHost string = rabbitmqContainer.properties.ipAddress.fqdn
output rabbitmqIp string = rabbitmqContainer.properties.ipAddress.ip
#disable-next-line outputs-should-not-contain-secrets
output rabbitmqUrl string = 'amqp://${rabbitmqUser}:${rabbitmqPassword}@${rabbitmqContainer.properties.ipAddress.fqdn}:5672'
output rabbitmqManagementUrl string = 'http://${rabbitmqContainer.properties.ipAddress.fqdn}:15672'
