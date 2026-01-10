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

1. **Azure CLI** installed ([Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
2. **GitHub CLI** installed ([Install GitHub CLI](https://cli.github.com/))
3. **Bicep CLI** (included with Azure CLI 2.20+)
4. **Azure Subscription** with Contributor access
5. **GitHub repository** with Actions enabled

### Step 1: Login to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### Step 2: Create Service Principal for GitHub Actions

```bash
# Create the Azure AD application
az ad app create --display-name "xshopai-github-actions"

# Get the app ID
APP_ID=$(az ad app list --display-name "xshopai-github-actions" --query "[0].appId" -o tsv)
echo "AZURE_CLIENT_ID: $APP_ID"

# Create service principal
az ad sp create --id $APP_ID

# Get tenant ID and subscription ID
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"

# Get service principal object ID
OBJECT_ID=$(az ad sp show --id $APP_ID --query "id" -o tsv)

# Create federated credential for GitHub Actions (main branch - for push triggers)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Create federated credential for 'dev' environment (REQUIRED for workflow_dispatch)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-dev-environment",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Assign Contributor role to subscription
az role assignment create \
  --assignee $OBJECT_ID \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Assign User Access Administrator role (required for creating role assignments for managed identity)
az role assignment create \
  --assignee $OBJECT_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

> **Note for Git Bash (Windows MINGW64)**: If the `az role assignment create` commands fail with path errors, prefix with `MSYS_NO_PATHCONV=1`:
> ```bash
> MSYS_NO_PATHCONV=1 az role assignment create --assignee $OBJECT_ID --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID"
> ```

### Step 3: Configure GitHub Repository Secrets

**Option A: Using GitHub CLI (Recommended)**

```bash
# Install GitHub CLI if not already installed: https://cli.github.com/

# Login to GitHub CLI
gh auth login

# Navigate to your repository (or use -R owner/repo flag)
cd /path/to/infrastructure

# Set Azure OIDC secrets (from Step 2 output)
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"

# Set database admin passwords (use strong passwords!)
gh secret set POSTGRES_ADMIN_PASSWORD --body "YourSecurePostgresPassword123!"
gh secret set SQL_SERVER_ADMIN_PASSWORD --body "YourSecureSqlPassword456!"
gh secret set MYSQL_ADMIN_PASSWORD --body "YourSecureMysqlPassword789!"

# Verify secrets are set
gh secret list
```

**Option B: Using GitHub UI**

Go to **GitHub → Repository → Settings → Secrets and variables → Actions** and add:

| Secret | Value | Description |
|--------|-------|-------------|
| `AZURE_CLIENT_ID` | `$APP_ID` from Step 2 | Service Principal Client ID |
| `AZURE_TENANT_ID` | `$TENANT_ID` from Step 2 | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `$SUBSCRIPTION_ID` from Step 2 | Azure Subscription ID |
| `POSTGRES_ADMIN_PASSWORD` | Your secure password | PostgreSQL admin password |
| `SQL_SERVER_ADMIN_PASSWORD` | Your secure password | SQL Server admin password |
| `MYSQL_ADMIN_PASSWORD` | Your secure password | MySQL admin password |

> **Password Requirements**: Use strong passwords (12+ chars, mixed case, numbers, symbols)

### Step 4: Deploy Infrastructure

**Option A: GitHub Actions (Recommended)**

1. Go to **Actions** → **"Deploy Azure Container Apps Infrastructure"**
2. Click **"Run workflow"**
3. Select branch: `main`
4. Select environment: `dev`
5. Click **"Run workflow"**

**Option B: Azure CLI (Manual)**

```bash
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

## 🔐 GitHub Secrets Reference

All secrets are configured in **Step 3** of Quick Start. Here's a complete reference:

| Secret | Description | Required For |
|--------|-------------|-------------|
| `AZURE_CLIENT_ID` | Service Principal Client ID | OIDC Authentication |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | OIDC Authentication |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | OIDC Authentication |
| `POSTGRES_ADMIN_PASSWORD` | PostgreSQL admin password | Database Creation |
| `SQL_SERVER_ADMIN_PASSWORD` | Azure SQL Server admin password | Database Creation |
| `MYSQL_ADMIN_PASSWORD` | MySQL Flexible Server admin password | Database Creation |

### Adding Federated Credentials for Other Branches

If you need to deploy from other branches (staging, releases), add additional federated credentials:

```bash
# For staging branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-staging",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:ref:refs/heads/staging",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For pull requests (optional)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
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