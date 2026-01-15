# xshopai Bicep Module Registry

Reusable Infrastructure-as-Code modules for deploying xshopai microservices to Azure Container Apps and Azure data services.

## 📦 Available Modules

| Module | Version | Description | Use Case |
|--------|---------|-------------|----------|
| `container-app` | v1.0.0 | Generic Container App deployment | All microservices |
| `mysql-database` | v1.0.0 | MySQL database on Flexible Server | Inventory, Order, Product services |
| `cosmos-database` | v1.0.0 | Cosmos DB SQL database | Cart, Notification services |
| `postgresql-database` | v1.0.0 | PostgreSQL database on Flexible Server | User, Review services |
| `sql-database` | v1.0.0 | Azure SQL database | Payment, Order services |

## 🚀 Quick Start

### 1. Configure Registry Access

Create `bicepconfig.json` in your service repository:

```json
{
  "$schema": "https://aka.ms/bicep/config-schema",
  "moduleAliases": {
    "br": {
      "xshopai": {
        "registry": "xshopaiacr.azurecr.io",
        "modulePath": "bicep/modules"
      }
    }
  }
}
```

### 2. Reference Modules in Your Bicep

```bicep
// Use semantic versioning for production
module containerApp 'br/xshopai:container-app:v1.0.0' = {
  name: 'inventory-service-container-app'
  params: {
    containerAppName: 'inventory-service'
    containerAppsEnvironmentId: containerAppsEnvironment.id
    containerImage: 'ghcr.io/xshopai/inventory-service:latest'
    containerPort: 8005
  }
}

// Use 'latest' tag for development only
module database 'br/xshopai:mysql-database:latest' = {
  name: 'inventory-database'
  params: {
    databaseName: 'inventory_db'
    mysqlServerName: 'mysql-xshopai-prod'
  }
}
```

## 📚 Module Documentation

### container-app

Deploys a Container App with Dapr, managed identity, and auto-scaling.

#### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `containerAppName` | string | Name of the Container App |
| `containerAppsEnvironmentId` | string | Resource ID of Container Apps Environment |
| `containerImage` | string | Full container image path (e.g., `ghcr.io/xshopai/service:tag`) |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region |
| `containerPort` | int | `8080` | Port the app listens on |
| `externalIngress` | bool | `true` | Enable external ingress |
| `targetPort` | int | `8080` | Ingress target port |
| `cpu` | string | `'0.5'` | CPU cores (0.25, 0.5, 1.0, 2.0) |
| `memory` | string | `'1.0Gi'` | Memory allocation |
| `minReplicas` | int | `1` | Minimum replica count |
| `maxReplicas` | int | `10` | Maximum replica count |
| `environmentVariables` | array | `[]` | Environment variables |
| `secrets` | array | `[]` | Secret values |
| `dapr.enabled` | bool | `true` | Enable Dapr sidecar |
| `dapr.appId` | string | `containerAppName` | Dapr app ID |
| `dapr.appPort` | int | `containerPort` | Dapr app port |

#### Outputs

| Output | Type | Description |
|--------|------|-------------|
| `containerAppId` | string | Resource ID |
| `fqdn` | string | Fully qualified domain name |
| `identityPrincipalId` | string | Managed identity principal ID |

#### Example: Full Configuration

```bicep
module inventoryService 'br/xshopai:container-app:v1.0.0' = {
  name: 'inventory-service-deployment'
  params: {
    containerAppName: 'inventory-service'
    location: 'eastus'
    containerAppsEnvironmentId: containerAppsEnv.id
    containerImage: 'ghcr.io/xshopai/inventory-service:v2.1.5'
    containerPort: 8005
    targetPort: 8005
    externalIngress: true
    cpu: '1.0'
    memory: '2.0Gi'
    minReplicas: 2
    maxReplicas: 20
    environmentVariables: [
      {
        name: 'SERVICE_PORT'
        value: '8005'
      }
      {
        name: 'LOG_LEVEL'
        value: 'info'
      }
      {
        name: 'MYSQL_HOST'
        secretRef: 'mysql-host'
      }
    ]
    secrets: [
      {
        name: 'mysql-host'
        value: mysqlServer.properties.fullyQualifiedDomainName
      }
      {
        name: 'mysql-password'
        value: keyVaultSecret.value
      }
    ]
    dapr: {
      enabled: true
      appId: 'inventory-service'
      appPort: 8005
      appProtocol: 'http'
      enableApiLogging: true
    }
  }
}
```

---

### mysql-database

Creates a MySQL database on an existing Flexible Server.

#### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `databaseName` | string | Name of the database to create |
| `mysqlServerName` | string | Name of existing MySQL Flexible Server |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `charset` | string | `'utf8mb4'` | Character set |
| `collation` | string | `'utf8mb4_unicode_ci'` | Collation |

#### Outputs

| Output | Type | Description |
|--------|------|-------------|
| `databaseId` | string | Database resource ID |
| `mysqlServerFqdn` | string | MySQL server FQDN |
| `connectionStringTemplate` | string | Connection string (replace `{password}`) |

#### Example

```bicep
module inventoryDb 'br/xshopai:mysql-database:v1.0.0' = {
  name: 'inventory-database'
  params: {
    databaseName: 'inventory_db'
    mysqlServerName: 'mysql-xshopai-prod'
    charset: 'utf8mb4'
    collation: 'utf8mb4_unicode_ci'
  }
}

// Use connection string in Container App
module inventoryService 'br/xshopai:container-app:v1.0.0' = {
  name: 'inventory-service'
  params: {
    containerAppName: 'inventory-service'
    containerAppsEnvironmentId: containerAppsEnv.id
    containerImage: 'ghcr.io/xshopai/inventory-service:latest'
    secrets: [
      {
        name: 'mysql-connection-string'
        value: replace(inventoryDb.outputs.connectionStringTemplate, '{password}', mysqlPassword)
      }
    ]
  }
}
```

---

### cosmos-database

Creates a Cosmos DB SQL database on an existing Cosmos account.

#### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `databaseName` | string | Name of the database to create |
| `cosmosAccountName` | string | Name of existing Cosmos DB account |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `throughput` | int | `400` | Manual throughput (RU/s). Use 0 for serverless. |
| `enableAutoscale` | bool | `false` | Enable autoscale |
| `maxAutoscaleThroughput` | int | `4000` | Max autoscale throughput |

#### Outputs

| Output | Type | Description |
|--------|------|-------------|
| `databaseId` | string | Database resource ID |
| `cosmosEndpoint` | string | Cosmos DB endpoint URL |
| `connectionString` | string | Primary connection string |

#### Example

```bicep
module cartDb 'br/xshopai:cosmos-database:v1.0.0' = {
  name: 'cart-database'
  params: {
    databaseName: 'cart_db'
    cosmosAccountName: 'cosmos-xshopai-prod'
    enableAutoscale: true
    maxAutoscaleThroughput: 4000
  }
}
```

---

### postgresql-database

Creates a PostgreSQL database on an existing Flexible Server.

#### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `databaseName` | string | Name of the database to create |
| `postgresServerName` | string | Name of existing PostgreSQL Flexible Server |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `charset` | string | `'UTF8'` | Character set |
| `collation` | string | `'en_US.utf8'` | Collation |

#### Outputs

| Output | Type | Description |
|--------|------|-------------|
| `databaseId` | string | Database resource ID |
| `postgresServerFqdn` | string | PostgreSQL server FQDN |
| `connectionStringTemplate` | string | Connection string (replace `{password}`) |

#### Example

```bicep
module userDb 'br/xshopai:postgresql-database:v1.0.0' = {
  name: 'user-database'
  params: {
    databaseName: 'user_db'
    postgresServerName: 'postgres-xshopai-prod'
  }
}
```

---

### sql-database

Creates an Azure SQL database on an existing SQL Server.

#### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `databaseName` | string | Name of the database to create |
| `sqlServerName` | string | Name of existing Azure SQL Server |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region |
| `sku` | object | `{name: 'Basic', tier: 'Basic', capacity: 5}` | Database SKU |
| `maxSizeBytes` | int | `2147483648` (2GB) | Maximum database size |
| `collation` | string | `'SQL_Latin1_General_CP1_CI_AS'` | Collation |
| `zoneRedundant` | bool | `false` | Enable zone redundancy |

#### Outputs

| Output | Type | Description |
|--------|------|-------------|
| `databaseId` | string | Database resource ID |
| `sqlServerFqdn` | string | SQL Server FQDN |
| `connectionStringTemplate` | string | Connection string (replace `{password}`) |

#### Example

```bicep
module orderDb 'br/xshopai:sql-database:v1.0.0' = {
  name: 'order-database'
  params: {
    databaseName: 'order_db'
    sqlServerName: 'sql-xshopai-prod'
    sku: {
      name: 'S1'
      tier: 'Standard'
      capacity: 20
    }
    maxSizeBytes: 10737418240 // 10GB
    zoneRedundant: true
  }
}
```

---

## 🔐 Authentication

### GitHub Actions OIDC

The publishing workflow uses OIDC authentication (no secrets required):

```yaml
- name: Azure Login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### Required Secrets

Configure these in your infrastructure repository:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Service principal application ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

## 📋 Best Practices

### 1. Version Pinning

**✅ DO** - Pin to specific versions in production:
```bicep
module app 'br/xshopai:container-app:v1.0.0' = { }
```

**❌ DON'T** - Use 'latest' in production:
```bicep
module app 'br/xshopai:container-app:latest' = { }
```

### 2. Parameter Files

Use `.bicepparam` files for environment-specific configuration:

```bicep
// dev.bicepparam
using './main.bicep'

param containerImage = 'ghcr.io/xshopai/inventory-service:dev'
param minReplicas = 1
param maxReplicas = 3
param cpu = '0.5'
param memory = '1.0Gi'
```

```bicep
// prod.bicepparam
using './main.bicep'

param containerImage = 'ghcr.io/xshopai/inventory-service:v2.1.5'
param minReplicas = 3
param maxReplicas = 20
param cpu = '2.0'
param memory = '4.0Gi'
```

### 3. Secrets Management

**✅ DO** - Use Azure Key Vault references:
```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: 'kv-xshopai-prod'
}

module app 'br/xshopai:container-app:v1.0.0' = {
  params: {
    secrets: [
      {
        name: 'mysql-password'
        value: keyVault.getSecret('mysql-password')
      }
    ]
  }
}
```

**❌ DON'T** - Hardcode secrets:
```bicep
secrets: [
  {
    name: 'mysql-password'
    value: 'MyP@ssw0rd123'  // NEVER DO THIS!
  }
]
```

### 4. Managed Identity

Always use system-assigned managed identity for Azure service access:

```bicep
module app 'br/xshopai:container-app:v1.0.0' = {
  params: {
    // ... other params
  }
}

// Grant Container App access to Key Vault
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-02-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app.outputs.identityPrincipalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}
```

### 5. Resource Naming

Follow consistent naming conventions:

```bicep
var resourceSuffix = '${environmentName}-${locationShort}'
var containerAppName = 'ca-${serviceName}-${resourceSuffix}'
var databaseName = '${serviceName}_db'

module app 'br/xshopai:container-app:v1.0.0' = {
  name: '${serviceName}-container-app-deployment'
  params: {
    containerAppName: containerAppName
  }
}
```

## 🔄 Module Updates

### Publishing New Versions

1. **Update module** in `azure/bicep/modules/`
2. **Commit changes** to feature branch
3. **Create PR** to main branch
4. **Merge PR** → workflow automatically publishes new version
5. **Version format**: `v1.0.{GITHUB_RUN_NUMBER}-{SHORT_SHA}`

### Manual Publishing

Trigger manual publishing with specific version:

```bash
# Via GitHub Actions UI
# Workflow: "Publish Bicep Modules to Registry"
# Input: version = v1.1.0
```

### Consuming Updates

Update version reference in service repository:

```bicep
// Before
module app 'br/xshopai:container-app:v1.0.0' = { }

// After
module app 'br/xshopai:container-app:v1.1.0' = { }
```

## 🧪 Testing Modules Locally

### Validate Before Publishing

```bash
cd azure/bicep/modules

# Validate syntax
az bicep build --file container-app.bicep

# Lint all modules
az bicep lint --file container-app.bicep
az bicep lint --file mysql-database.bicep
az bicep lint --file cosmos-database.bicep
```

### Test Module Deployment

Create a test Bicep file:

```bicep
// test-container-app.bicep
param containerAppsEnvironmentId string = '/subscriptions/.../containerApps/ca-env-test'

module testApp './modules/container-app.bicep' = {
  name: 'test-deployment'
  params: {
    containerAppName: 'test-app'
    containerAppsEnvironmentId: containerAppsEnvironmentId
    containerImage: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
  }
}
```

Deploy to test environment:

```bash
az deployment group create \
  --resource-group rg-xshopai-test \
  --template-file test-container-app.bicep
```

## 📞 Support

- **Issues**: Report bugs in infrastructure repository
- **Questions**: Contact platform team on Slack #xshopai-infrastructure
- **Documentation**: See [Infrastructure Wiki](https://github.com/xshopai/infrastructure/wiki)

## 📝 Changelog

### v1.0.0 (2026-01-15)
- ✨ Initial release of Bicep module registry
- 📦 5 reusable modules: container-app, mysql-database, cosmos-database, postgresql-database, sql-database
- 🤖 Automated publishing via GitHub Actions
- 📚 Complete documentation with examples
