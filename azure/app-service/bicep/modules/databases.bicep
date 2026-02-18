// Databases module - Cosmos DB, PostgreSQL, MySQL, SQL Server
param location string
param environment string
param shortEnv string
param keyVaultName string
param tags object

// Cosmos DB (MongoDB API) for audit-service
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: 'cosmos-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    mongoEndpoint: 'https://cosmos-xshopai-gh-${shortEnv}.mongo.cosmos.azure.com:443/'
    capabilities: [
      {
        name: 'EnableMongo'
      }
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
  }
}

// Cosmos DB MongoDB database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: 'audit-db'
  properties: {
    resource: {
      id: 'audit-db'
    }
  }
}

// PostgreSQL Flexible Server (for user-service, notification-service)
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: 'psql-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '15'
    administratorLogin: 'xshopadmin'
    administratorLoginPassword: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/postgres-password/)'
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

// PostgreSQL firewall rule (allow Azure services)
resource postgresFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// MySQL Flexible Server (for review-service, admin-service)
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = {
  name: 'mysql-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1s'
    tier: 'Burstable'
  }
  properties: {
    version: '8.0.21'
    administratorLogin: 'xshopadmin'
    administratorLoginPassword: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/mysql-password/)'
    storage: {
      storageSizeGB: 20
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

// MySQL firewall rule
resource mysqlFirewall 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-06-30' = {
  parent: mysqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL Server (for order-service, payment-service, cart-service)
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: 'sql-xshopai-gh-${shortEnv}'
  location: location
  tags: tags
  properties: {
    administratorLogin: 'xshopadmin'
    administratorLoginPassword: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/sqlserver-password/)'
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// SQL firewall rule
resource sqlFirewall 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL Databases
resource cartDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: 'cart-db'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

resource orderDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: 'order-db'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

resource paymentDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: 'payment-db'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

// Outputs
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output postgresHost string = postgresServer.properties.fullyQualifiedDomainName
output mysqlHost string = mysqlServer.properties.fullyQualifiedDomainName
output sqlServerHost string = sqlServer.properties.fullyQualifiedDomainName
