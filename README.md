# xshopai Infrastructure

Infrastructure as Code (IaC) for the xshopai e-commerce platform.

## 🏗️ Structure

```
infrastructure/
├── azure/
│   ├── container-apps/          # Azure Container Apps (PRIMARY)
│   │   └── bicep/
│   │       ├── deploy.bicep     # Subscription-scoped entry point (creates RG)
│   │       ├── main.bicep       # Resource group-scoped orchestration
│   │       ├── modules/         # Reusable modules
│   │       └── parameters/      # Environment parameters
│   └── aks/                     # Azure Kubernetes Service (FUTURE)
│
├── aws/                         # AWS (FUTURE)
│   ├── ecs/                     # ECS + Fargate
│   └── eks/                     # EKS
│
├── .github/
│   └── workflows/
│       └── azure-container-apps-deploy.yml  # Infrastructure deployment
│
└── shared/                      # Shared configurations
    └── services/                # Service definitions
```

### Bicep Deployment Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    SUBSCRIPTION SCOPE (deploy.bicep)                     │
│                                                                          │
│  1. Creates Resource Group                                               │
│  2. Calls main.bicep as module scoped to the resource group              │
│                                                                          │
│  az deployment sub create --template-file deploy.bicep                   │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     │
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                   RESOURCE GROUP SCOPE (main.bicep)                      │
│                                                                          │
│  Deploys all Azure resources:                                            │
│  • Container Apps Environment    • Key Vault                             │
│  • Container Registry (ACR)      • Log Analytics                         │
│  • Service Bus                   • Managed Identity                      │
│  • Redis Cache                   • Databases (SQL, PostgreSQL, MySQL,    │
│  • Cosmos DB (MongoDB API)         Cosmos DB)                            │
│                                                                          │
│  Can also be deployed directly to existing RG:                           │
│  az deployment group create --template-file main.bicep                   │
└──────────────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

1. Azure CLI installed and logged in
2. Bicep CLI (comes with Azure CLI)
3. GitHub repository secrets configured

### Deploy to Azure Container Apps

```bash
# 1. Login to Azure
az login

# 2. Deploy infrastructure (creates resource group + all resources)
az deployment sub create \
  --location uksouth \
  --template-file azure/container-apps/bicep/deploy.bicep \
  --parameters azure/container-apps/bicep/parameters/dev.bicepparam \
  --parameters postgresAdminPassword=<your-postgres-password> \
  --parameters sqlServerAdminPassword=<your-sqlserver-password> \
  --parameters mysqlAdminPassword=<your-mysql-password>
```

Or deploy resources only (if resource group exists):

```bash
az deployment group create \
  --resource-group rg-xshopai-dev \
  --template-file azure/container-apps/bicep/main.bicep \
  --parameters azure/container-apps/bicep/parameters/dev.bicepparam \
  --parameters postgresAdminPassword=<your-postgres-password> \
  --parameters sqlServerAdminPassword=<your-sqlserver-password> \
  --parameters mysqlAdminPassword=<your-mysql-password>
```

Or use GitHub Actions (recommended):

1. Go to Actions → "Deploy Azure Container Apps Infrastructure"
2. Select environment (dev/staging/prod)
3. Click "Run workflow"

## 📦 What Gets Deployed

| Resource | Purpose | Used By |
|----------|---------|---------|
| Container Apps Environment | Hosts all services with Dapr | All services |
| Container Registry (ACR) | Stores Docker images | All services |
| Service Bus | Dapr pub/sub messaging | Event-driven services |
| Redis Cache | Dapr state store + caching | cart-service (via Dapr) |
| Cosmos DB (MongoDB API) | Document database | user, product, review, notification, cart, auth services |
| Azure SQL Server | .NET services database | order-service, payment-service |
| PostgreSQL | Java/Node services database | order-processor-service, audit-service |
| MySQL Flexible Server | Python services database | inventory-service |
| Key Vault | Secrets management | All services |
| Log Analytics | Centralized logging | All services |
| Managed Identity | Secure Azure access | All services |

### Database Architecture

The platform uses a **Platform Team Model** for database management:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PLATFORM TEAM MODEL                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  INFRASTRUCTURE REPO (this repo)           SERVICE REPOS                    │
│  ────────────────────────────             ─────────────                     │
│  Creates DATABASE SERVERS only:            Each service creates its OWN:    │
│  • Azure SQL Server                        • Database on the server         │
│  • PostgreSQL Flexible Server              • Tables/collections/schemas     │
│  • MySQL Flexible Server                   • Runs migrations at deploy      │
│  • Cosmos DB Account (MongoDB API)                                          │
│                                                                             │
│  Stores in Key Vault:                      Retrieves from Key Vault:        │
│  • Server admin credentials                • Admin credentials              │
│  • Server FQDNs                           • Connection string templates     │
│  • Connection string templates                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Why this approach?**
- **Service Autonomy**: Each service owns its database schema and migrations
- **Clear Responsibility**: Infrastructure = servers, Services = databases
- **CI/CD Integration**: Services run migrations during deployment
- **Security**: Admin credentials stored securely in Key Vault

#### Database Server Mapping

| Database Server | Type | Services (create their own DB) |
|-----------------|------|-------------------------------|
| Azure SQL Server | sql-server.bicep | order-service, payment-service |
| PostgreSQL | postgresql.bicep | order-processor-service, audit-service |
| MySQL | mysql.bicep | inventory-service |
| Cosmos DB (MongoDB) | cosmos-db.bicep | user-service, product-service, review-service, notification-service, cart-service |
| Redis Cache | redis.bicep | cart-service (Dapr state store) |

#### Key Vault Secrets for Databases

Each database module stores credentials in Key Vault:

```
┌────────────────────────────────────────────────────────────────┐
│ KEY VAULT SECRETS                                              │
├────────────────────────────────────────────────────────────────┤
│ sql-server-admin-login        SQL Server admin username        │
│ sql-server-admin-password     SQL Server admin password        │
│ sql-server-fqdn               SQL Server fully qualified name  │
├────────────────────────────────────────────────────────────────┤
│ postgresql-admin-login        PostgreSQL admin username        │
│ postgresql-admin-password     PostgreSQL admin password        │
│ postgresql-server-fqdn        PostgreSQL server FQDN           │
├────────────────────────────────────────────────────────────────┤
│ mysql-admin-login             MySQL admin username             │
│ mysql-admin-password          MySQL admin password             │
│ mysql-server-fqdn             MySQL server FQDN                │
├────────────────────────────────────────────────────────────────┤
│ cosmos-db-connection-string   MongoDB connection string        │
│ cosmos-db-account-name        Cosmos DB account name           │
│ cosmos-db-document-endpoint   Cosmos DB endpoint URL           │
│ cosmos-db-primary-key         Cosmos DB primary key            │
└────────────────────────────────────────────────────────────────┘
```

#### Service Database Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│               SERVICE DEPLOYMENT WORKFLOW                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Service CI/CD workflow runs                                 │
│                                                                 │
│  2. Retrieve database credentials from Key Vault                │
│     az keyvault secret show --name sql-server-admin-password    │
│                                                                 │
│  3. Create database if not exists                               │
│     sqlcmd -S $FQDN -U $ADMIN -P $PASSWORD                      │
│     -Q "CREATE DATABASE IF NOT EXISTS order_service_db"         │
│                                                                 │
│  4. Run migrations                                              │
│     dotnet ef database update                                   │
│     (or equivalent for your framework)                          │
│                                                                 │
│  5. Deploy application container                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🔐 GitHub Secrets Required

Configure these in your GitHub repository settings:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Service Principal Client ID |
| `AZURE_TENANT_ID` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID |
| `POSTGRES_ADMIN_PASSWORD` | PostgreSQL admin password |
| `SQL_SERVER_ADMIN_PASSWORD` | Azure SQL Server admin password |
| `MYSQL_ADMIN_PASSWORD` | MySQL Flexible Server admin password |

### Setting up Azure OIDC Authentication

```bash
# Create service principal with OIDC
az ad app create --display-name "xshopai-github-actions"

# Get the app ID
APP_ID=$(az ad app list --display-name "xshopai-github-actions" --query "[0].appId" -o tsv)

# Create service principal
az ad sp create --id $APP_ID

# Get object ID
OBJECT_ID=$(az ad sp show --id $APP_ID --query "id" -o tsv)

# Create federated credential for GitHub Actions
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Assign Contributor role
az role assignment create \
  --assignee $OBJECT_ID \
  --role "Contributor" \
  --scope "/subscriptions/<subscription-id>"
```

## 🌐 Environments

| Environment | Resource Group | Purpose |
|-------------|---------------|---------|
| `dev` | rg-xshopai-dev | Development and testing |
| `staging` | rg-xshopai-staging | Pre-production validation |
| `prod` | rg-xshopai-prod | Production workloads |

## 📋 Dapr Components

The infrastructure configures these Dapr components:

| Component | Type | Backing Service |
|-----------|------|-----------------|
| `pubsub` | pubsub.azure.servicebus.topics | Azure Service Bus |
| `statestore` | state.redis | Azure Cache for Redis |
| `secretstore` | secretstores.azure.keyvault | Azure Key Vault |
| `configstore` | configuration.redis | Azure Cache for Redis |

## 🔄 Service Deployment

After infrastructure is deployed, each service deploys itself using its own GitHub Actions workflow:

```
user-service/.github/workflows/deploy.yml     → Deploys ca-user-service
auth-service/.github/workflows/deploy.yml     → Deploys ca-auth-service
cart-service/.github/workflows/deploy.yml     → Deploys ca-cart-service
...
```

Services reference the shared infrastructure:
- Push images to the shared ACR
- Deploy Container Apps to the shared environment
- Use shared Dapr components

## 📚 Documentation

- [Azure Container Apps Setup](docs/AZURE-CONTAINER-APPS.md)
- [Adding a New Service](docs/ADDING-NEW-SERVICE.md)
- [Dapr Components](docs/DAPR-COMPONENTS.md)
- [Operations Runbook](docs/RUNBOOK.md)

## 🛠️ Local Development

For local development, services use local Dapr components (RabbitMQ, Redis) defined in each service's `.dapr/components/` folder. No Azure infrastructure is required for local development.

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.