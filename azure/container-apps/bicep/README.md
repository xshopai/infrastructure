# Azure Container Apps - Bicep Modules

Reusable Bicep modules for deploying xshopai microservices to Azure Container Apps.

## 📁 Structure

```
azure/container-apps/bicep/
├── bicepconfig.json              # Registry alias configuration
├── README.md                     # This documentation
├── bicep-registry/               # Bicep registry infrastructure
│   ├── main.bicep               # ACR + shared resources deployment
│   ├── parameters.prod.json     # Production parameters
│   └── README.md                # Registry setup documentation
├── modules/                      # Reusable Bicep modules
│   ├── acr.bicep                # Azure Container Registry
│   ├── container-app.bicep      # Container App (main service module)
│   ├── container-apps-environment.bicep  # Container Apps Environment
│   ├── cosmos-database.bicep    # Cosmos DB (MongoDB/SQL API)
│   ├── dapr-components.bicep    # Dapr components configuration
│   ├── key-vault.bicep          # Azure Key Vault
│   ├── key-vault-secret.bicep   # Individual secret
│   ├── key-vault-secrets.bicep  # Bulk secrets
│   ├── log-analytics.bicep      # Log Analytics workspace
│   ├── managed-identity.bicep   # User-assigned managed identity
│   ├── mysql-database.bicep     # Azure MySQL Flexible Server
│   ├── postgresql-database.bicep # Azure PostgreSQL Flexible Server
│   ├── redis.bicep              # Azure Cache for Redis
│   ├── resource-group.bicep     # Resource group with location
│   ├── service-bus.bicep        # Azure Service Bus
│   ├── sql-database.bicep       # Azure SQL Database
│   └── sql-server.bicep         # Azure SQL Server
└── parameters/                   # Environment-specific parameters
    ├── dev.bicepparam           # Development environment
    └── prod.bicepparam          # Production environment
```

## 🌍 Environments

The platform supports two environments:

| Environment | Purpose | Resource Group |
|-------------|---------|----------------|
| **dev** | Development/testing | `rg-xshopai-dev` |
| **prod** | Production workloads | `rg-xshopai-prod` |

## 🚀 Using Modules

### Option 1: Direct Reference (Local Development)

```bicep
module containerApp 'modules/container-app.bicep' = {
  name: 'deploy-product-service'
  params: {
    name: 'product-service'
    environmentId: containerAppsEnv.outputs.id
    containerImage: 'xshopai.azurecr.io/product-service:latest'
    targetPort: 8001
    daprEnabled: true
    daprAppId: 'product-service'
  }
}
```

### Option 2: Azure Container Registry (CI/CD)

After publishing to ACR:

```bicep
module containerApp 'br/xshopai:container-app:v1.0.0' = {
  name: 'deploy-product-service'
  params: {
    name: 'product-service'
    environmentId: containerAppsEnv.outputs.id
    containerImage: 'xshopai.azurecr.io/product-service:latest'
  }
}
```

## 📦 Module Reference

### Core Modules

| Module | Purpose | Key Parameters |
|--------|---------|----------------|
| `resource-group.bicep` | Create resource groups | `name`, `location` |
| `container-apps-environment.bicep` | Container Apps host | `name`, `logAnalyticsWorkspaceId` |
| `container-app.bicep` | Deploy a service | `name`, `containerImage`, `targetPort`, `daprEnabled` |
| `acr.bicep` | Container registry | `name`, `sku` |

### Infrastructure Modules

| Module | Purpose | Key Parameters |
|--------|---------|----------------|
| `key-vault.bicep` | Secrets management | `name`, `enableRbacAuthorization` |
| `key-vault-secret.bicep` | Add single secret | `keyVaultName`, `secretName`, `secretValue` |
| `log-analytics.bicep` | Logging/monitoring | `name`, `retentionInDays` |
| `managed-identity.bicep` | Service identity | `name` |

### Database Modules

| Module | Database | Key Parameters |
|--------|----------|----------------|
| `mysql-database.bicep` | MySQL Flexible | `serverName`, `databaseName`, `adminUser` |
| `postgresql-database.bicep` | PostgreSQL Flexible | `serverName`, `databaseName`, `adminUser` |
| `cosmos-database.bicep` | Cosmos DB | `accountName`, `databaseName`, `apiType` |
| `sql-database.bicep` | Azure SQL | `serverName`, `databaseName` |
| `redis.bicep` | Redis Cache | `name`, `sku`, `capacity` |

### Messaging Modules

| Module | Purpose | Key Parameters |
|--------|---------|----------------|
| `service-bus.bicep` | Message broker | `namespaceName`, `queueNames`, `topicNames` |
| `dapr-components.bicep` | Dapr configuration | `environmentId`, `componentConfigs` |

## 🔐 Registry Configuration

The `bicepconfig.json` configures the ACR alias:

```json
{
  "moduleAliases": {
    "br": {
      "xshopai": {
        "registry": "xshopaimodules.azurecr.io",
        "modulePath": "bicep/container-apps"
      }
    }
  }
}
```

## 📋 Publishing Modules

Modules are published via GitHub Actions workflow:

```bash
# Manual publish (requires Azure CLI login)
az bicep publish \
  --file modules/container-app.bicep \
  --target br:xshopaimodules.azurecr.io/bicep/container-apps/container-app:v1.0.0
```

## 🏷️ Versioning

Modules use semantic versioning:
- `v1.0.0` - Initial release
- `v1.1.0` - New features (backward compatible)
- `v2.0.0` - Breaking changes

## 🔗 Related Documentation

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Dapr on Container Apps](https://learn.microsoft.com/azure/container-apps/dapr-overview)
