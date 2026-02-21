# xshopai App Service Deployment Scripts

Manual deployment scripts for deploying xshopai platform to Azure App Service.

## Prerequisites

1. **Azure CLI** installed and configured

   ```bash
   # Install Azure CLI
   # https://docs.microsoft.com/cli/azure/install-azure-cli

   # Login to Azure
   az login
   ```

2. **Docker** installed and running (for building service images)

3. **Bash shell** (Git Bash on Windows, Terminal on macOS/Linux)

4. **Subscription Contributor access** on your Azure subscription

## Quick Start

```bash
# Navigate to bash scripts directory
cd infrastructure/azure/app-service/bash

# Make scripts executable (Linux/macOS)
chmod +x deploy.sh deploy-infra.sh modules/*.sh modules/services/*.sh

# Full deployment (infrastructure + all services)
./deploy.sh

# Or with environment specified
./deploy.sh development swedencentral
```

## Deployment Options

```bash
# Full deployment (default)
./deploy.sh

# Infrastructure only (no services)
./deploy.sh --infra-only

# Services only (requires existing infrastructure)
./deploy.sh --services-only

# Single service deployment
./deploy.sh --service auth-service
./deploy.sh --service customer-ui

# Infrastructure-only script (alternative)
./deploy-infra.sh development swedencentral
```

## What Gets Deployed

### Infrastructure

| Resource                | Development SKU    | Production SKU     |
| ----------------------- | ------------------ | ------------------ |
| Resource Group          | -                  | -                  |
| Log Analytics Workspace | PerGB2018          | PerGB2018          |
| Application Insights    | -                  | -                  |
| Key Vault (RBAC)        | Standard           | Standard           |
| Container Registry      | Basic              | Standard           |
| App Service Plan        | B1 (Linux)         | P1v2 (Linux)       |
| Redis Cache             | Basic C0           | Standard C1        |
| Cosmos DB (MongoDB)     | Serverless         | Provisioned        |
| PostgreSQL Flexible     | Burstable B1ms     | General D2s        |
| MySQL Flexible          | Burstable B1ms     | General D2ds       |
| SQL Server              | Serverless Gen5    | Serverless Gen5    |
| RabbitMQ                | Container Instance | Container Instance |

### Services (16 total)

| Service                 | Runtime     | Database         | Port |
| ----------------------- | ----------- | ---------------- | ---- |
| auth-service            | Node.js 18  | MongoDB (Cosmos) | 8003 |
| user-service            | Node.js 18  | MongoDB (Cosmos) | 8002 |
| product-service         | Python 3.11 | MongoDB (Cosmos) | 8001 |
| inventory-service       | Python 3.11 | MySQL            | 8005 |
| audit-service           | Node.js 18  | MongoDB (Cosmos) | 8010 |
| notification-service    | Node.js 18  | MongoDB (Cosmos) | 8011 |
| review-service          | Node.js 18  | MongoDB (Cosmos) | 8005 |
| admin-service           | Node.js 18  | MongoDB (Cosmos) | 8012 |
| cart-service            | Java 17     | MySQL            | 8007 |
| chat-service            | Node.js 18  | MySQL            | 8013 |
| order-processor-service | Java 17     | SQL Server       | 8008 |
| order-service           | .NET 8.0    | SQL Server       | 8006 |
| payment-service         | .NET 8.0    | SQL Server       | 8009 |
| web-bff                 | Node.js 18  | None             | 8014 |
| customer-ui             | Node.js 18  | None             | 80   |
| admin-ui                | Node.js 18  | None             | 80   |

## Script Structure

```
bash/
├── deploy.sh                # Main entry point (infra + services)
├── deploy-infra.sh          # Infrastructure only
├── README.md
└── modules/
    ├── common.sh            # Shared functions and variables
    ├── 01-resource-group.sh # Resource group creation
    ├── 02-monitoring.sh     # Log Analytics + App Insights
    ├── 03-keyvault.sh       # Key Vault with RBAC
    ├── 04-acr.sh            # Container Registry
    ├── 05-app-service-plan.sh # App Service Plan
    ├── 06-redis.sh          # Redis Cache
    ├── 07-cosmos-db.sh      # Cosmos DB (MongoDB API)
    ├── 08-postgresql.sh     # PostgreSQL Flexible Server
    ├── 09-mysql.sh          # MySQL Flexible Server
    ├── 10-sql-server.sh     # SQL Server + Databases
    ├── 11-rabbitmq.sh       # RabbitMQ Container Instance
    ├── 12-secrets.sh        # Store secrets in Key Vault
    └── services/            # Individual service deployment
        ├── _common.sh       # Service deployment helpers
        ├── auth-service.sh
        ├── user-service.sh
        ├── product-service.sh
        ├── inventory-service.sh
        ├── audit-service.sh
        ├── notification-service.sh
        ├── review-service.sh
        ├── admin-service.sh
        ├── cart-service.sh
        ├── chat-service.sh
        ├── order-processor-service.sh
        ├── order-service.sh
        ├── payment-service.sh
        ├── web-bff.sh
        ├── customer-ui.sh
        └── admin-ui.sh
```

## How Services Reference Infrastructure

Each service module (`modules/services/*.sh`) contains:

1. **Service-specific configuration** - Runtime, port, database type
2. **Environment variables** - Connection strings, service URLs
3. **Docker build** - Builds image from source
4. **ACR push** - Pushes to Azure Container Registry
5. **App Service deployment** - Deploys container

Example from `auth-service.sh`:

```bash
deploy_auth_service() {
    local settings=(
        "MONGODB_URI=$COSMOS_CONNECTION"           # From Key Vault
        "JWT_SECRET=$JWT_SECRET"                   # From Key Vault
        "REDIS_HOST=$REDIS_HOST"                   # From infrastructure
        "USER_SERVICE_URL=https://app-user-service-${PROJECT_NAME}-${SHORT_ENV}.azurewebsites.net"
    )
    deploy_service_full "auth-service" "NODE|18-lts" "8003" "${settings[@]}"
}
```

## Environment Variables Flow

1. **Infrastructure deployment** creates resources and stores secrets in Key Vault
2. **Service deployment** reads secrets from Key Vault
3. **App Services** receive environment variables via `az webapp config appsettings`
4. **Service code** reads environment variables at runtime

## Key Features

- **Modular** - Each service has its own deployment script
- **Idempotent** - Can be safely re-run
- **Self-contained** - All config in individual service files
- **Docker-based** - Builds and deploys container images
- **Key Vault integration** - All secrets stored securely
- **Environment aware** - Different SKUs for dev/prod

## Redeploying a Single Service

After code changes, redeploy just that service:

```bash
# Set environment if not already set
export ENVIRONMENT=development

# Deploy single service
./deploy.sh --service auth-service
```

## Troubleshooting

### Script fails with "permission denied"

```bash
chmod +x deploy.sh deploy-infra.sh modules/*.sh modules/services/*.sh
```

### Docker not available

The script will create App Services but skip image building. Run again with Docker.

### Key Vault access denied

Wait 20-30 seconds for RBAC propagation after Key Vault creation.

### Service deployment fails

Check the log file at `/tmp/xshopai-deploy-*.log` for details.

## Cleanup

To delete all resources:

```bash
az group delete --name rg-xshopai-gh-development --yes --no-wait
```
