// Redis Cache module
param location string
param environment string
param shortEnv string
param tags object

resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: 'redis-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// Outputs
output redisHost string = redisCache.properties.hostName
output redisKey string = redisCache.listKeys().primaryKey
