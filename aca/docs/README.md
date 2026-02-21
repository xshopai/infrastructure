# xshopai Infrastructure Deployment for Azure Container Apps

This folder contains scripts to deploy the shared infrastructure for the xshopai microservices platform on Azure Container Apps.

## Overview

The infrastructure deployment creates all shared Azure resources that are used by multiple services. This approach provides:

- **Cost Efficiency**: Shared resources (Service Bus, Redis, etc.) are created once
- **Consistency**: All services use the same infrastructure with consistent naming
- **Simplified Service Deployment**: Service scripts only need to deploy their container apps

## Resources Created

| Resource                   | Naming Pattern                  | Description                       |
| -------------------------- | ------------------------------- | --------------------------------- |
| Resource Group             | `rg-xshopai-{env}-{suffix}`     | Contains all resources            |
| Managed Identity           | `id-xshopai-{env}-{suffix}`     | Service authentication            |
| Container Registry         | `xshopai{env}{suffix}`          | Stores Docker images              |
| Log Analytics              | `law-xshopai-{env}-{suffix}`    | Centralized logging               |
| Application Insights       | `appi-xshopai-{env}-{suffix}`   | Application monitoring            |
| Container Apps Environment | `cae-xshopai-{env}-{suffix}`    | Hosting environment               |
| Service Bus                | `sb-xshopai-{env}-{suffix}`     | Message broker for Dapr pub/sub   |
| Redis Cache                | `redis-xshopai-{env}-{suffix}`  | Caching and Dapr state store      |
| Cosmos DB (account)        | `cosmos-xshopai-{env}-{suffix}` | MongoDB API server (no databases) |
| MySQL Server               | `mysql-xshopai-{env}-{suffix}`  | MySQL server (no databases)       |
| SQL Server                 | `sql-xshopai-{env}-{suffix}`    | Azure SQL Server (Azure AD auth)  |
| Key Vault                  | `kv-xshopai-{env}-{suffix}`     | Secrets management                |

> **Note**: The `{suffix}` is a 3-6 character alphanumeric string (e.g., `b96d`) that ensures globally unique resource names and avoids conflicts after deletions.

### What's NOT Created by Infrastructure

Individual **databases** are NOT created by this script. Each service creates its own database during deployment to ensure:

- **Service Autonomy**: Each service owns and manages its data
- **Correct Naming**: Services define their own database names based on their requirements
- **Schema Control**: Services handle their own migrations and collections/tables

| Service           | Database Type | Database Created By Service |
| ----------------- | ------------- | --------------------------- |
| user-service      | Cosmos DB     | Service's `aca.sh`          |
| product-service   | Cosmos DB     | Service's `aca.sh`          |
| review-service    | Cosmos DB     | Service's `aca.sh`          |
| inventory-service | Cosmos DB     | Service's `aca.sh`          |
| audit-service     | Cosmos DB     | Service's `aca.sh`          |
| cart-service      | Cosmos DB     | Service's `aca.sh`          |
| order-service     | SQL Server    | Infra script + migrations   |
| payment-service   | SQL Server    | Service's `aca.sh`          |

### SQL Server with Managed Identity (Azure AD Authentication)

Order service uses **Azure SQL Server with Azure AD authentication** via managed identity. This is required for Azure subscriptions with MCAPS (Microsoft Secure Future Initiative) policies that prohibit SQL username/password authentication.

**How it works:**

1. Infrastructure script creates `order_service_db` in SQL Server
2. Managed identity `id-xshopai-{env}-{suffix}` is granted SQL roles:
   - `db_datareader` - Read data
   - `db_datawriter` - Write data
   - `db_ddladmin` - Create/modify tables (for EF Core migrations)
3. Service deployment sets `AZURE_CLIENT_ID` env var for `DefaultAzureCredential`
4. EF Core migrations run automatically at startup

**Connection string format:**

```
Server=sql-xshopai-dev-{suffix}.database.windows.net;
Database=order_service_db;
Authentication=Active Directory Default;
TrustServerCertificate=True;
Encrypt=True
```

> **Note**: No password in connection string - authentication uses managed identity token.

## Prerequisites

1. **Azure CLI** installed and logged in:

   ```bash
   az login
   az account set --subscription "Your Subscription Name"
   ```

2. **Sufficient Permissions**:
   - Contributor role on the subscription (to create resources)
   - User Access Administrator role (to assign RBAC)

3. **Required Azure CLI Extensions**:
   ```bash
   az extension add --name containerapp --upgrade
   az extension add --name servicebus --upgrade
   ```

## Usage

### Bash (Linux/macOS/Git Bash)

```bash
cd infrastructure/azure/aca/scripts

# Deploy to development environment
./deploy-infra.sh dev

# Deploy to staging environment
./deploy-infra.sh staging

# Deploy to production environment
./deploy-infra.sh prod
```

### PowerShell (Windows)

```powershell
cd infrastructure\azure\aca\scripts

# Deploy to development environment
.\deploy-infra.ps1 -Environment dev

# Deploy to staging environment
.\deploy-infra.ps1 -Environment staging

# Deploy to production environment
.\deploy-infra.ps1 -Environment prod
```

## Deployment Time

The full infrastructure deployment takes approximately **15-20 minutes** thanks to parallel resource creation:

| Resource                         | Individual Time | Runs In      |
| -------------------------------- | --------------- | ------------ |
| Resource Group, Identity, ACR    | ~2 min          | Sequential   |
| Log Analytics, App Insights, CAE | ~5 min          | Sequential   |
| Service Bus                      | ~2 min          | Sequential   |
| **Redis + Cosmos DB + MySQL**    | **~10-15 min**  | **Parallel** |
| Key Vault + Secrets + Dapr       | ~3 min          | Sequential   |

> **Optimization**: Redis, Cosmos DB, and MySQL are created in parallel, reducing total time from ~30 minutes to ~15 minutes.

## Naming Conventions

### Standard Resources (hyphens allowed)

```
{resource-type}-{project}-{environment}-{suffix}
```

Examples: `rg-xshopai-dev-b96d`, `cae-xshopai-prod-abc1`

### Restricted Resources (no hyphens)

```
{resourcetype}{project}{environment}{suffix}
```

Examples: `xshopaidevb96d` (ACR)

## Environment Variables

After deployment, the script outputs environment variables needed for service deployments:

```bash
export RESOURCE_GROUP="rg-xshopai-dev-b96d"
export ACR_NAME="xshopaidevb96d"
export ACR_LOGIN_SERVER="xshopaidevb96d.azurecr.io"
export CONTAINER_ENV="cae-xshopai-dev-b96d"
export MANAGED_IDENTITY_ID="/subscriptions/.../id-xshopai-dev-b96d"
export APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=..."
export SUFFIX="b96d"
```

> **Important**: Save the `SUFFIX` value - you'll need it for all service deployments.

## Dapr Components

The script automatically configures the following Dapr components:

### 1. Pub/Sub (Service Bus)

- **Component Name**: `pubsub`
- **Type**: `pubsub.azure.servicebus.topics`
- **Scoped To**: All backend services

### 2. State Store (Redis)

- **Component Name**: `statestore`
- **Type**: `state.redis`
- **Scoped To**: cart-service, order-service, user-service, auth-service

### 3. Secret Store (Key Vault)

- **Component Name**: `secretstore`
- **Type**: `secretstores.azure.keyvault`
- **Authentication**: Managed Identity

## Secrets Stored in Key Vault

| Secret Name                          | Description                                |
| ------------------------------------ | ------------------------------------------ |
| `xshopai-servicebus-connection`      | Service Bus connection string              |
| `xshopai-redis-password`             | Redis access key                           |
| `xshopai-cosmos-account-connection`  | Cosmos DB account connection string        |
| `xshopai-mysql-server-connection`    | MySQL server connection (URL format)       |
| `xshopai-postgres-server-connection` | PostgreSQL server connection (JDBC format) |
| `xshopai-sql-server-connection`      | SQL Server connection (Azure AD auth)      |
| `xshopai-appinsights-connection`     | Application Insights connection string     |
| `xshopai-jwt-secret`                 | JWT signing secret                         |
| `xshopai-flask-secret`               | Flask session secret (Python services)     |
| `svc-product-token`                  | Product service identity token             |
| `svc-order-token`                    | Order service identity token               |
| `svc-cart-token`                     | Cart service identity token                |
| `svc-webbff-token`                   | Web BFF identity token                     |

**Naming Convention:**

- `xshopai-{resource}-{type}-connection` for database/service connections (server/account level)
- `xshopai-{name}` for other platform-wide secrets
- `svc-{service}-token` for service identity tokens

## Network Security & Firewall Configuration

The deployment scripts automatically configure firewall rules and network access for all resources:

### Service-to-Service Communication

| Resource               | Security Configuration               | Notes                                                                                  |
| ---------------------- | ------------------------------------ | -------------------------------------------------------------------------------------- |
| **Service Bus**        | Trusted Azure services allowed       | Enables Container Apps to publish/subscribe to messages                                |
| **Redis Cache**        | Access key + TLS 1.2                 | Basic/Standard tiers don't support VNet rules; Premium tier recommended for production |
| **Cosmos DB**          | Azure services allowed (IP: 0.0.0.0) | Allows Container Apps and Azure Portal access                                          |
| **MySQL**              | Azure services firewall rule         | `AllowAllAzureServices` rule (0.0.0.0-0.0.0.0)                                         |
| **SQL Server**         | Azure AD only + Managed Identity     | No SQL username/password - uses managed identity for authentication                    |
| **Key Vault**          | RBAC + Azure services bypass         | Managed Identity authentication with AzureServices bypass                              |
| **Container Registry** | Managed Identity (AcrPull)           | Services authenticate via assigned identity                                            |

### Production Security Recommendations

For production environments, consider implementing:

1. **VNet Integration**

   ```bash
   # Create Container Apps Environment with VNet
   az containerapp env create \
     --name $ContainerEnv \
     --resource-group $ResourceGroup \
     --infrastructure-subnet-resource-id $SubnetId
   ```

2. **Private Endpoints** for databases and Key Vault:
   - Cosmos DB Private Endpoint
   - MySQL Private Endpoint
   - Key Vault Private Endpoint
   - Service Bus Private Endpoint

3. **Premium Redis** with VNet integration:

   ```bash
   az redis create --sku Premium --vm-size p1 \
     --subnet-id $SubnetId
   ```

4. **Restrict MySQL to specific IPs**:

   ```bash
   # Get Container Apps Environment outbound IPs
   az containerapp env show --name $ContainerEnv \
     --resource-group $ResourceGroup \
     --query "properties.staticIp"

   # Add specific firewall rule
   az mysql flexible-server firewall-rule create \
     --rule-name "ContainerAppsOnly" \
     --start-ip-address <OUTBOUND_IP> \
     --end-ip-address <OUTBOUND_IP>
   ```

5. **Network Security Groups (NSGs)** for VNet-integrated environments

### Current Security Posture (Development)

The default configuration prioritizes ease of development:

- ✅ All services can communicate within Azure
- ✅ TLS encryption enforced where applicable
- ✅ Managed Identity for authentication
- ✅ Secrets stored in Key Vault (not in code)
- ⚠️ Public network access enabled (for Portal/CLI access)
- ⚠️ Azure-wide firewall rules (not service-specific IPs)

## After Deployment

Once infrastructure is deployed, deploy services using their individual scripts:

```bash
# Example: Deploy user-service
cd user-service/scripts
./aca.sh dev

# Example: Deploy product-service
cd product-service/scripts
./aca.sh dev
```

## Troubleshooting

### "Resource already exists"

The scripts are idempotent and will skip resources that already exist. This is expected behavior.

### "Insufficient permissions"

Ensure you have:

- Contributor role on the subscription
- User Access Administrator role for RBAC assignments

### Redis creation timeout

Redis can take up to 20 minutes to provision. If timeout occurs, wait and re-run the script.

### Key Vault secret errors

If running with a service principal, you may need to manually add secrets:

```bash
az keyvault secret set --vault-name kv-xshopai-dev --name "secret-name" --value "secret-value"
```

## Cost Estimates

| Resource                   | SKU            | Estimated Monthly Cost (USD) |
| -------------------------- | -------------- | ---------------------------- |
| Container Apps Environment | Consumption    | ~$0.40/million requests      |
| Container Registry         | Basic          | ~$5                          |
| Service Bus                | Standard       | ~$10                         |
| Redis Cache                | Basic C0       | ~$16                         |
| Cosmos DB                  | Serverless     | ~$25 (based on usage)        |
| MySQL                      | Burstable B1ms | ~$12                         |
| Key Vault                  | Standard       | ~$0.03/secret/month          |
| Log Analytics              | Pay-as-you-go  | ~$2.30/GB                    |

**Estimated Total**: ~$70-100/month for development environment

## Cleanup

To delete all infrastructure:

```bash
# Delete the entire resource group (removes all resources)
# Replace {suffix} with your actual suffix (e.g., b96d)
az group delete --name rg-xshopai-dev-{suffix} --yes --no-wait
```

⚠️ **Warning**: This permanently deletes all data including databases and secrets.

## Support

For issues with infrastructure deployment, check:

1. Azure CLI version: `az version`
2. Subscription permissions: `az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv)`
3. Resource provider registrations: `az provider list --query "[?registrationState=='Registered'].namespace" -o table`
