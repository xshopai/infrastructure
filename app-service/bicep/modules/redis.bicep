// =============================================================================
// Azure Cache for Redis - Basic C0 (can be upgraded to Standard for production)
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Resource naming prefix (xshopai-{env}-{suffix})')
param resourcePrefix string

@description('Resource tags')
param tags object

@description('Redis SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

@description('Redis cache size (C0-C6 for Basic/Standard)')
@allowed(['C0', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6'])
param vmSize string = 'C0'

// =============================================================================
// Variables
// =============================================================================

var redisName = 'redis-${resourcePrefix}'

// =============================================================================
// Resources
// =============================================================================

resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: redisName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
      family: startsWith(vmSize, 'C') ? 'C' : 'P'
      capacity: int(substring(vmSize, 1))
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output redisId string = redis.id
output redisName string = redis.name
output redisHost string = redis.properties.hostName
#disable-next-line outputs-should-not-contain-secrets
output redisPrimaryKey string = redis.listKeys().primaryKey
#disable-next-line outputs-should-not-contain-secrets
output redisSecondaryKey string = redis.listKeys().secondaryKey
output redisSslPort int = redis.properties.sslPort
output redisPort int = redis.properties.port
