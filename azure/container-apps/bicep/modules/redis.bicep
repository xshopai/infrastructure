// ============================================================================
// Azure Cache for Redis Module
// Used for Dapr state store and application caching
// ============================================================================

@description('Name of the Redis Cache')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('SKU for Redis')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

@description('Capacity (0=250MB, 1=1GB, 2=2.5GB, etc.)')
@minValue(0)
@maxValue(6)
param capacity int = 0

@description('Enable non-SSL port')
param enableNonSslPort bool = false

@description('Minimum TLS version')
@allowed(['1.0', '1.1', '1.2'])
param minimumTlsVersion string = '1.2'

// ============================================================================
// Resources
// ============================================================================

resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
      family: sku == 'Premium' ? 'P' : 'C'
      capacity: capacity
    }
    enableNonSslPort: enableNonSslPort
    minimumTlsVersion: minimumTlsVersion
    publicNetworkAccess: 'Enabled'
    redisConfiguration: {
      'maxmemory-policy': 'volatile-lru'
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Redis Cache Resource ID')
output id string = redisCache.id

@description('Redis Cache Name')
output name string = redisCache.name

@description('Redis Host Name')
output hostName string = redisCache.properties.hostName

@description('Redis SSL Port')
output sslPort int = redisCache.properties.sslPort

#disable-next-line outputs-should-not-contain-secrets
@description('Redis Primary Key (stored in Key Vault for secure access)')
output primaryKey string = redisCache.listKeys().primaryKey

#disable-next-line outputs-should-not-contain-secrets
@description('Redis Connection String (stored in Key Vault for secure access)')
output connectionString string = '${redisCache.properties.hostName}:${redisCache.properties.sslPort},password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
