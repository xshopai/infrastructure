// RabbitMQ Container Instance module
param location string
param environment string
param shortEnv string
param tags object

var containerGroupName = 'aci-rabbitmq-${shortEnv}'

resource rabbitmqContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  tags: tags
  properties: {
    containers: [
      {
        name: 'rabbitmq'
        properties: {
          image: 'rabbitmq:3-management'
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 2
            }
          }
          ports: [
            {
              port: 5672
              protocol: 'TCP'
            }
            {
              port: 15672
              protocol: 'TCP'
            }
          ]
          environmentVariables: [
            {
              name: 'RABBITMQ_DEFAULT_USER'
              value: 'admin'
            }
            {
              name: 'RABBITMQ_DEFAULT_PASS'
              secureValue: 'RabbitMQ@${environment}2024!'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 5672
          protocol: 'TCP'
        }
        {
          port: 15672
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: 'rabbitmq-xshopai-${environment}'
    }
  }
}

// Outputs
output rabbitMQHost string = rabbitmqContainer.properties.ipAddress.fqdn
output rabbitMQIP string = rabbitmqContainer.properties.ipAddress.ip
output rabbitMQManagementUrl string = 'http://${rabbitmqContainer.properties.ipAddress.fqdn}:15672'
