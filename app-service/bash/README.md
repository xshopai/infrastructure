# xshopai App Service Deployment Scripts

Native (no Docker) deployment scripts for deploying the xshopai platform to Azure App Service.
Services are deployed using their native runtimes (Node.js, Python, Java, .NET) via Oryx build-on-deploy or local Maven/dotnet publish.

## Prerequisites

1. **Azure CLI** installed and logged in

   ```bash
   # Install: https://docs.microsoft.com/cli/azure/install-azure-cli
   az login
   ```

2. **dotnet CLI** — required for building .NET services (order-service, payment-service)

3. **Maven (mvn)** — required for building Java services (cart-service, order-processor-service)

4. **Bash shell** — Git Bash on Windows, Terminal on macOS/Linux

5. **Subscription Contributor access** on your Azure subscription

## Quick Start

```bash
# Navigate to bash scripts directory
cd infrastructure/azure/app-service/bash

# Make scripts executable (Linux/macOS)
chmod +x deploy.sh common.sh infra/*.sh services/*.sh

# Full deployment (infrastructure + all services) — interactive
./deploy.sh

# Or with all options specified (non-interactive)
./deploy.sh --env dev --location francecentral --suffix abc123
```

## Deployment Options

```bash
# Full deployment — infrastructure + all services (default when no flags given)
./deploy.sh

# Infrastructure only
./deploy.sh --infra

# Services only (requires existing infrastructure)
./deploy.sh --services

# Single service redeployment
./deploy.sh --service auth-service
./deploy.sh --service customer-ui

# Specify environment and location
./deploy.sh --env prod --location westeurope --suffix mysfx
```

## What Gets Deployed

### Infrastructure

| Resource                | SKU                     |
| ----------------------- | ----------------------- |
| Resource Group          | —                       |
| Log Analytics Workspace | PerGB2018, 30-day retention |
| Application Insights    | Workspace-based (shared)|
| Key Vault               | Standard                |
| App Service Plan        | P3V3 (Linux)            |
| Redis Cache             | Standard C1             |
| Cosmos DB (MongoDB API) | Serverless              |
| PostgreSQL Flexible     | Burstable B1ms          |
| MySQL Flexible          | Burstable B1ms          |
| SQL Server              | Serverless Gen5         |
| RabbitMQ                | Container Instance (ACI)|

### Services (16 total)

All services listen on port **8080** (Azure App Service Linux default).

| Service                 | Runtime      | Database           |
| ----------------------- | ------------ | ------------------ |
| auth-service            | Node.js 18   | —                  |
| user-service            | Node.js 18   | MongoDB (Cosmos)   |
| product-service         | Python 3.11  | MongoDB (Cosmos)   |
| inventory-service       | Python 3.11  | MySQL              |
| audit-service           | Node.js 18   | PostgreSQL         |
| notification-service    | Node.js 18   | —                  |
| review-service          | Node.js 18   | MongoDB (Cosmos)   |
| admin-service           | Node.js 18   | —                  |
| cart-service            | Java 17      | Redis              |
| chat-service            | Node.js 18   | —                  |
| order-processor-service | Java 17      | PostgreSQL         |
| order-service           | .NET 8.0     | SQL Server         |
| payment-service         | .NET 8.0     | SQL Server         |
| web-bff                 | Node.js 18   | —                  |
| customer-ui             | Node.js 18   | —                  |
| admin-ui                | Node.js 18   | —                  |

All services publish events via **RabbitMQ** and send telemetry to shared **Application Insights**.

## Script Structure

```
bash/
├── deploy.sh          # Main entry point (infra + services)
├── common.sh          # Shared functions and resource naming
├── README.md
├── infra/             # Infrastructure modules (run in order)
│   ├── 01-resource-group.sh
│   ├── 02-monitoring.sh       # Log Analytics + App Insights
│   ├── 03-app-service-plan.sh
│   ├── 04-redis.sh
│   ├── 05-cosmos-db.sh
│   ├── 06-postgresql.sh
│   ├── 07-mysql.sh
│   ├── 08-sql-server.sh
│   ├── 09-rabbitmq.sh         # RabbitMQ on ACI
│   └── 10-keyvault.sh         # Key Vault + all secrets
└── services/          # Per-service deployment scripts
    ├── _common.sh             # deploy_service_full(), build helpers
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

## How Services Are Deployed

Each service script calls `deploy_service_full` from `services/_common.sh`, which:

1. Creates the App Service (or updates if it already exists)
2. Assigns a system-managed identity
3. Sets all environment variables via `az webapp config appsettings`
4. Configures health check path and diagnostic settings
5. Builds and deploys the service using its native runtime:
   - **Node.js / Python** — zips source, uploads; Oryx builds on App Service (`npm install` / `pip install`)
   - **Java** — runs `mvn package` locally, deploys the JAR
   - **.NET** — runs `dotnet publish` locally, deploys a zip

Example from `auth-service.sh`:

```bash
deploy_auth_service() {
    local service_name="auth-service"
    local runtime="NODE|18-lts"
    local port="8080"
    local settings=(
        "JWT_SECRET=$(load_secret jwt-secret)"
        "RABBITMQ_URL=$(load_secret rabbitmq-url)"
        # ...
    )
    deploy_service_full "$service_name" "$runtime" "$port" "${settings[@]}"
}
```

## Environment Variables Flow

1. `infra/10-keyvault.sh` stores all secrets (connection strings, passwords, tokens) in Key Vault
2. Each service script calls `load_secret <name>` to read from Key Vault at deploy time
3. Secrets are injected into the App Service as app settings via `az webapp config appsettings set`
4. Service code reads them as standard environment variables at runtime

## Key Features

- **No Docker required** — native runtime deployment via Oryx and local builds
- **Modular** — each service has its own deployment script
- **Idempotent** — safe to re-run; existing resources are detected and skipped
- **Parallel infra** — Redis, Cosmos, PostgreSQL, MySQL, and SQL Server deploy concurrently
- **Key Vault integration** — all secrets stored and read securely
- **Shared Application Insights** — end-to-end distributed tracing across all services

## Redeploying a Single Service

After code changes, redeploy just that service (infrastructure must already exist):

```bash
./deploy.sh --env dev --suffix <your-suffix> --service auth-service
```

## Troubleshooting

### Permission denied on scripts

```bash
chmod +x deploy.sh common.sh infra/*.sh services/*.sh
```

### Key Vault access denied

Wait 20–30 seconds after Key Vault creation for RBAC propagation, then retry.

### Java/dotnet build fails

Ensure `mvn` and `dotnet` are installed and on your `PATH` before running the script.

### Service deployment fails

Check the log file printed at the start of the run:

```
Log file: /tmp/xshopai-deploy-YYYYMMDD-HHMMSS.log
```

## Cleanup

To delete all resources (replace `<suffix>` and `<env>` with your values):

```bash
az group delete --name rg-xshopai-<env>-<suffix> --yes --no-wait
```
