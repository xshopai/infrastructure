# Azure Container Apps - Deployment Guide

Complete guide for deploying the xshopai microservices platform to Azure Container Apps from scratch.

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Deployment Phases](#deployment-phases)
5. [Architecture](#architecture)
6. [Resource Naming](#resource-naming)
7. [Module Catalog](#module-catalog)
8. [Environment Configuration](#environment-configuration)
9. [Troubleshooting](#troubleshooting)
10. [Cost Management](#cost-management)

---

## Overview

### Architecture Approach

This deployment uses a **modular, registry-based Bicep architecture**:

- **15 reusable Bicep modules** published to Azure Container Registry
- **Environment-specific orchestration** (dev/prod) with parameter files
- **Dapr integration** for service mesh (pub/sub, state, secrets, config)
- **OIDC authentication** for GitHub Actions (no service principal secrets)
- **Zero-downtime deployments** via GitHub Actions

### Key Design Principles

1. **Modular Design**: Each infrastructure component is a standalone, versioned module
2. **Registry Pattern**: Modules published to ACR (`xshopaimodules.azurecr.io`) for reuse
3. **Server-Only Pattern**: Database servers deployed; app databases created via migrations
4. **Event-Driven**: Service Bus + Dapr pub/sub for async communication (9 topics)
5. **Security-First**: RBAC, managed identities, Key Vault, TLS 1.2+, OIDC
6. **Observability**: Log Analytics workspace for centralized monitoring

---

## Prerequisites

### Required Tools

| Tool       | Version | Installation                                                      |
| ---------- | ------- | ----------------------------------------------------------------- |
| Azure CLI  | 2.50+   | `az upgrade` or [download](https://aka.ms/installazurecliwindows) |
| Git        | 2.40+   | `winget install Git.Git`                                          |
| PowerShell | 7.3+    | `winget install Microsoft.PowerShell`                             |

### Azure Requirements

- Active Azure subscription with **Contributor** or **Owner** role
- Ability to create Azure AD applications
- Sufficient quotas: Container Apps, ACR Premium, Databases

### GitHub Requirements

- GitHub organization (e.g., `xshopai`)
- Admin access to configure secrets
- Actions enabled for CI/CD

---

## Quick Start

Deploy the complete platform in 5 commands:

```bash
# 1. Clone repository
cd c:/gh/xshopai/infrastructure/scripts/azure

# 2. Login to Azure
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# 3. Setup Azure OIDC (one-time)
./setup-azure-oidc.sh

# 4. Deploy infrastructure (~20 minutes)
gh workflow run deploy-platform-infrastructure.yml \
  --field environment=dev \
  --field location=swedencentral \
  --field dry_run=false

# 5. Deploy microservices (~15 minutes)
cd ../../../  # Navigate to each service repo
# Deploy each service via its GitHub Actions workflow
```

**Total deployment time**: ~35-40 minutes

---

## Deployment Phases

### Phase 0: Azure & GitHub Setup (One-Time)

**Goal**: Configure OIDC authentication for GitHub Actions.

#### Why OIDC?

- ✅ No `AZURE_CLIENT_SECRET` stored in GitHub
- ✅ Token auto-rotated by Azure
- ✅ Scoped per environment (dev/prod)
- ✅ Better security posture

#### Step 1: Setup Azure OIDC

```bash
cd infrastructure/scripts/azure
./setup-azure-oidc.sh
```

**Script creates**:

1. Azure AD App Registration: `xshopai-github-actions`
2. Service Principal with `Contributor` role
3. Federated credentials for `environment:dev` and `environment:prod`
4. Configures OIDC subject customization (environment-only) in all repos

**Expected output**:

```
✅ Azure AD App created: xshopai-github-actions
✅ Federated credentials configured (dev, prod)
✅ OIDC customization configured for 17 repositories

📋 Configure these GitHub Secrets:
   AZURE_CLIENT_ID=abc-123...
   AZURE_TENANT_ID=def-456...
   AZURE_SUBSCRIPTION_ID=ghi-789...
```

#### Step 2: Create GitHub Environments

**⚠️ CRITICAL**: GitHub environments must exist for OIDC authentication to work!

```bash
# Still in infrastructure/scripts/azure directory
./setup-github-environments.sh
```

**Script creates**:

- `dev` environment in all 17 repositories (infrastructure + 16 services)
- `prod` environment in all 17 repositories
- These match the federated credential subjects: `environment:dev` and `environment:prod`

**Why required?**:

- Azure federated credentials authenticate based on `environment:dev|prod` claim
- Without GitHub environments, workflows can't authenticate to Azure
- Environments enable deployment protection rules (manual approval for prod)

**Expected output**:

```
✅ Environment Setup Complete!

📊 Summary:
   Repositories processed: 17
   Environments created: 34

Each repository now has 2 environments:
   • dev  - Development environment (no protection)
   • prod - Production environment (manual approval optional)
```

**Verify environments were created**:

```bash
gh api repos/xshopai/product-service/environments
```

#### Step 3: Configure GitHub Secrets

**⚠️ REQUIRED**: Configure all 6 secrets before deploying infrastructure!

##### Option A: Automated Script (Recommended)

```bash
# Configure all secrets automatically
./setup-github-secrets.sh
```

The script will prompt you for:
- Azure OIDC credentials (from Step 1 output)
- Database admin passwords (you create these)

##### Option B: Manual Configuration (GitHub CLI)

```bash
# Azure OIDC Secrets (from setup-azure-oidc.sh output)
gh secret set AZURE_CLIENT_ID --body "abc-123-def-456..."
gh secret set AZURE_TENANT_ID --body "tenant-id-here"
gh secret set AZURE_SUBSCRIPTION_ID --body "subscription-id-here"

# Database Admin Passwords (create secure passwords)
gh secret set POSTGRES_ADMIN_PASSWORD --body "YourSecurePostgresPassword123!"
gh secret set SQL_ADMIN_PASSWORD --body "YourSecureSqlPassword123!"
gh secret set MYSQL_ADMIN_PASSWORD --body "YourSecureMySQLPassword123!"
```

##### Option C: GitHub UI

1. Navigate to: **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** (or **New organization secret** for all repos)
3. Add each secret below

##### Complete Secrets Reference

| Secret                     | Value                    | Purpose                                      | Used By                |
| -------------------------- | ------------------------ | -------------------------------------------- | ---------------------- |
| `AZURE_CLIENT_ID`          | From script output       | Azure AD App Registration ID for OIDC        | All deployment workflows |
| `AZURE_TENANT_ID`          | From script output       | Azure AD Tenant ID                           | All deployment workflows |
| `AZURE_SUBSCRIPTION_ID`    | From script output       | Azure Subscription ID                        | All deployment workflows |
| `POSTGRES_ADMIN_PASSWORD`  | You create (secure!)     | Admin password for PostgreSQL servers        | Platform infrastructure  |
| `SQL_ADMIN_PASSWORD`       | You create (secure!)     | Admin password for SQL Server                | Platform infrastructure  |
| `MYSQL_ADMIN_PASSWORD`     | You create (secure!)     | Admin password for MySQL server              | Platform infrastructure  |

##### Password Requirements

**Must meet Azure complexity requirements**:
- Minimum 8 characters (16+ recommended)
- Include uppercase, lowercase, numbers, special characters
- Example: `MySecure$Pass123!`

**Security Best Practices**:
- Use different passwords for each database
- Store passwords in a password manager
- Rotate passwords every 90 days
- Never commit passwords to Git

##### Environment-Specific Secrets (Optional)

For different passwords in dev/prod:

```bash
# Set environment-specific secrets
gh secret set POSTGRES_ADMIN_PASSWORD --env dev --body "DevPassword123!"
gh secret set POSTGRES_ADMIN_PASSWORD --env prod --body "ProdPassword456!"
```

##### Verify Secrets are Configured

```bash
# List all repository secrets
gh secret list

# Expected output:
# AZURE_CLIENT_ID          Updated 2025-01-16
# AZURE_TENANT_ID          Updated 2025-01-16
# AZURE_SUBSCRIPTION_ID    Updated 2025-01-16
# POSTGRES_ADMIN_PASSWORD  Updated 2025-01-16
# SQL_ADMIN_PASSWORD       Updated 2025-01-16
# MYSQL_ADMIN_PASSWORD     Updated 2025-01-16
```

---

### Phase 1: Bootstrap Infrastructure

**Goal**: Deploy Azure Container Registry for hosting Bicep modules.

#### Deploy Bootstrap

```bash
# Via GitHub Actions
gh workflow run deploy-bootstrap-infrastructure.yml \
  --field environment=dev \
  --field location=swedencentral
```

**Resources created**:

- Resource Group: `rg-xshopai-dev`
- Azure Container Registry: `xshopaimodulesdev.azurecr.io` (Premium SKU)

**Validation**:

```bash
az acr show --name xshopaimodulesdev
az acr login --name xshopaimodulesdev
```

---

### Phase 2: Publish Bicep Modules

**Goal**: Publish 15 reusable modules to ACR.

#### Publish Modules

```bash
# Via GitHub Actions
gh workflow run publish-bicep-modules.yml \
  --field environment=dev \
  --field version=v1.0.0
```

**Published modules** (15 total):

```
br:xshopaimodules dev.azurecr.io/bicep/container-apps/
├── acr:v1.0.0
├── container-app:v1.0.0
├── container-apps-environment:v1.0.0
├── cosmos-database:v1.0.0
├── key-vault:v1.0.0
├── log-analytics:v1.0.0
├── managed-identity:v1.0.0
├── mysql-database:v1.0.0
├── postgresql-database:v1.0.0
├── redis-cache:v1.0.0
├── resource-group:v1.0.0
├── service-bus:v1.0.0
├── sql-server:v1.0.0
├── sql-database:v1.0.0
└── key-vault-secrets:v1.0.0
```

**Validation**:

```bash
# List modules
az acr repository list --name xshopaimodulesdev --output table

# Check specific version
az acr repository show-tags \
  --name xshopaimodulesdev \
  --repository bicep/container-apps/container-app
```

---

### Phase 3: Platform Infrastructure

**Goal**: Deploy shared resources (databases, messaging, Container Apps Environment).

#### Deploy Platform

```bash
# Via GitHub Actions
gh workflow run deploy-platform-infrastructure.yml \
  --field environment=dev \
  --field location=swedencentral \
  --field dry_run=false  # Set true for what-if analysis
```

**Resources deployed** (~14-17 resources):

| Resource                   | Name                       | Purpose                     |
| -------------------------- | -------------------------- | --------------------------- |
| Resource Group             | `rg-xshopai-dev`           | Container for all resources |
| Log Analytics              | `log-xshopai-dev`          | Centralized logging         |
| Container Apps Environment | `cae-xshopai-dev`          | App hosting platform        |
| Managed Identity           | `id-xshopai-dev`           | Azure resource access       |
| Key Vault                  | `kv-xshopai-dev`           | Secrets storage             |
| PostgreSQL                 | `psql-xshopai-product-dev` | Product database            |
| PostgreSQL                 | `psql-xshopai-user-dev`    | User database               |
| PostgreSQL                 | `psql-xshopai-order-dev`   | Order database              |
| Cosmos DB                  | `cosmos-xshopai-dev`       | NoSQL database              |
| SQL Server                 | `sql-xshopai-dev`          | Relational database         |
| Redis Cache                | `redis-xshopai-dev`        | Caching layer               |
| Service Bus                | `sb-xshopai-dev`           | Event messaging             |

**Validation**:

```bash
# Check deployment
az deployment sub show \
  --name platform-infra-dev \
  --query properties.provisioningState

# List resources
az resource list --resource-group rg-xshopai-dev --output table

# Test Container Apps Environment
az containerapp env show \
  --name cae-xshopai-dev \
  --resource-group rg-xshopai-dev
```

---

### Phase 4: Microservice Deployment

**Goal**: Deploy 12 containerized microservices.

#### Service List

| Service                  | Language | Port | GitHub Workflow Command                                             |
| ------------------------ | -------- | ---- | ------------------------------------------------------------------- |
| **auth-service**         | Node.js  | 8002 | `gh workflow run cd-deploy.yml --repo xshopai/auth-service`         |
| **user-service**         | Node.js  | 8002 | `gh workflow run cd-deploy.yml --repo xshopai/user-service`         |
| **product-service**      | Python   | 8001 | `gh workflow run cd-deploy.yml --repo xshopai/product-service`      |
| **inventory-service**    | Python   | 8004 | `gh workflow run cd-deploy.yml --repo xshopai/inventory-service`    |
| **cart-service**         | Java     | 8005 | `gh workflow run cd-deploy.yml --repo xshopai/cart-service`         |
| **order-service**        | .NET     | 8006 | `gh workflow run cd-deploy.yml --repo xshopai/order-service`        |
| **payment-service**      | .NET     | 8009 | `gh workflow run cd-deploy.yml --repo xshopai/payment-service`      |
| **notification-service** | Node.js  | 8008 | `gh workflow run cd-deploy.yml --repo xshopai/notification-service` |
| **audit-service**        | Node.js  | 8009 | `gh workflow run cd-deploy.yml --repo xshopai/audit-service`        |
| **review-service**       | Node.js  | 8010 | `gh workflow run cd-deploy.yml --repo xshopai/review-service`       |
| **web-bff**              | Node.js  | 3100 | `gh workflow run cd-deploy.yml --repo xshopai/web-bff`              |
| **customer-ui**          | React    | 3000 | `gh workflow run cd-deploy.yml --repo xshopai/customer-ui`          |

#### Deploy Script (Automated)

```bash
# Deploy all services
for service in auth-service user-service product-service inventory-service \
               cart-service order-service payment-service notification-service \
               audit-service review-service web-bff customer-ui; do
    cd ../$service
    gh workflow run cd-deploy.yml --field environment=dev
done
```

**Validation**:

```bash
# List all apps
az containerapp list \
  --resource-group rg-xshopai-dev \
  --output table

# Check app health
az containerapp show \
  --name product-service \
  --resource-group rg-xshopai-dev \
  --query "properties.{status:runningStatus,replicas:template.scale.maxReplicas}"

# View logs
az containerapp logs show \
  --name product-service \
  --resource-group rg-xshopai-dev \
  --follow
```

---

## Architecture

### Runtime Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           Azure Container Apps Environment                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Dapr Sidecar Injection (Service Mesh)         │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │  auth    │ │  user    │ │ product  │ │  order   │ │  │
│  │  │ +Dapr    │ │ +Dapr    │ │ +Dapr    │ │ +Dapr    │ │  │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ │  │
│  └───────┼────────────┼────────────┼────────────┼────────┘  │
│          │            │            │            │            │
│          ▼            ▼            ▼            ▼            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │          Dapr Components (5 types)                    │  │
│  │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐        │  │
│  │ │pubsub│ │state │ │secret│ │config│ │bind  │        │  │
│  │ └───┬──┘ └───┬──┘ └───┬──┘ └───┬──┘ └───┬──┘        │  │
│  └─────┼────────┼────────┼────────┼────────┼────────────┘  │
└────────┼────────┼────────┼────────┼────────┼───────────────┘
         │        │        │        │        │
         ▼        ▼        ▼        ▼        ▼
   ┌──────────┐ ┌────┐ ┌───────┐ ┌────┐ ┌──────────┐
   │ Service  │ │Redis│ │  Key  │ │Redis│ │ Service  │
   │   Bus    │ │     │ │ Vault │ │     │ │   Bus    │
   └──────────┘ └────┘ └───────┘ └────┘ └──────────┘
        │
        ▼
   ┌─────────────────────────────┐
   │       Databases             │
   │ ┌─────────┐ ┌─────────┐    │
   │ │Cosmos DB│ │PostgreSQL│   │
   │ │(MongoDB)│ │          │    │
   │ └─────────┘ └─────────┘    │
   └─────────────────────────────┘
```

### Deployment Architecture

```
Phase 0: Azure AD Setup (OIDC)
    └─ App Registration + Federated Credentials

Phase 1: Bootstrap
    └─ ACR (xshopaimodules.azurecr.io)

Phase 2: Module Publishing
    └─ 15 Bicep modules → ACR

Phase 3: Platform Infrastructure
    ├─ Container Apps Environment
    ├─ 3x PostgreSQL Servers
    ├─ Cosmos DB
    ├─ SQL Server
    ├─ Redis Cache
    ├─ Service Bus
    ├─ Key Vault
    └─ Log Analytics

Phase 4: Microservices
    └─ 12 Container Apps (with Dapr)
```

---

## Resource Naming

All resources follow the pattern: `{type}-xshopai-{environment}[-suffix]`

| Resource Type      | Dev                       | Prod                       | Notes                   |
| ------------------ | ------------------------- | -------------------------- | ----------------------- |
| Resource Group     | `rg-xshopai-dev`          | `rg-xshopai-prod`          | Container for resources |
| Container Apps Env | `cae-xshopai-dev`         | `cae-xshopai-prod`         | App platform            |
| ACR                | `xshopaimodulesdev`       | `xshopaimodulesprod`       | Globally unique         |
| Key Vault          | `kv-xshopai-dev`          | `kv-xshopai-prod`          | Secrets storage         |
| Service Bus        | `sb-xshopai-dev`          | `sb-xshopai-prod`          | Event messaging         |
| Cosmos DB          | `cosmos-xshopai-dev`      | `cosmos-xshopai-prod`      | NoSQL database          |
| PostgreSQL         | `psql-xshopai-{name}-dev` | `psql-xshopai-{name}-prod` | 3 instances             |
| Redis              | `redis-xshopai-dev`       | `redis-xshopai-prod`       | Cache                   |
| Managed Identity   | `id-xshopai-dev`          | `id-xshopai-prod`          | Azure access            |
| Log Analytics      | `log-xshopai-dev`         | `log-xshopai-prod`         | Monitoring              |

---

## Module Catalog

### Core Platform (3 modules)

#### `resource-group.bicep`

- Creates subscription-scope resource group
- Parameters: `name`, `location` (20+ regions supported)
- Outputs: `id`, `name`, `location`

#### `log-analytics.bicep`

- Centralized monitoring workspace
- Parameters: `name`, `location`, `retentionInDays` (30-730)
- Outputs: `workspaceId`, `customerId`, `primarySharedKey`

#### `container-apps-environment.bicep`

- Managed hosting platform for Container Apps
- Parameters: `name`, `location`, `logAnalyticsWorkspaceId`
- Features: Dapr enabled, VNet integration, zone redundancy
- Outputs: `id`, `defaultDomain`, `staticIp`

### Data Layer (6 modules)

#### `cosmos-database.bicep`

- NoSQL database (MongoDB/SQL/Cassandra APIs)
- Parameters: `name`, `apiType`, `serverless` (true/false)
- Outputs: `connectionString`, `resourceId`

#### `postgresql-database.bicep`

- PostgreSQL Flexible Server
- Parameters: `serverName`, `administratorLogin`, `version` (11-15)
- Outputs: `serverFqdn`, `connectionStringTemplate`

#### `mysql-database.bicep`

- MySQL Flexible Server
- Parameters: `serverName`, `version` (5.7/8.0), `sku`
- Outputs: `serverFqdn`, `connectionStringTemplate`

#### `sql-server.bicep`

- SQL Server with Azure AD authentication
- Parameters: `baseName`, `administratorLogin`, `keyVaultName`
- Features: Firewall rules, Key Vault integration
- Outputs: `serverFqdn`, `serverId`

#### `redis-cache.bicep`

- Azure Cache for Redis
- Parameters: `name`, `sku` (Basic/Standard/Premium), `capacity` (0-6)
- Security: TLS 1.2+, SSL-only
- Outputs: `hostName`, `primaryKey`, `connectionString`

### Security & Identity (3 modules)

#### `managed-identity.bicep`

- User-assigned managed identity for services
- Parameters: `name`, `location`, `tags`
- Outputs: `id`, `principalId`, `clientId`

#### `key-vault.bicep`

- Secrets management with RBAC
- Parameters: `name`, `enableRbacAuthorization` (true)
- Features: Soft delete (90 days), purge protection
- Outputs: `name`, `uri`, `resourceId`

#### `key-vault-secrets.bicep`

- Bulk secret creation
- Parameters: `keyVaultName`, `secrets` (array of {name, value})
- Outputs: `secretNames`, `secretCount`

### Messaging & Dapr (2 modules)

#### `service-bus.bicep`

- Event-driven messaging backbone
- Creates: Namespace + 9 topics (order, payment, inventory, etc.)
- Features: RBAC role assignment to managed identity
- Outputs: `namespaceName`, `connectionString`, `endpoint`

#### `dapr-components.bicep` (Planned)

- Configures 5 Dapr component types
- Components: pubsub, statestore, secretstore, configstore, bindings

### Application Layer (2 modules)

#### `acr.bicep`

- Azure Container Registry
- Parameters: `name`, `sku` (Basic/Standard/Premium)
- Outputs: `name`, `loginServer`, `resourceId`

#### `container-app.bicep`

- Individual microservice deployment
- Parameters: 15 config options (image, CPU, memory, Dapr, etc.)
- Features: Auto-scaling (0-30 replicas), health probes, Dapr sidecar
- Outputs: `fqdn`, `url`, `latestRevisionName`

---

## Environment Configuration

### Accessing Secrets via Dapr

Services retrieve secrets from Key Vault at runtime using Dapr secret store component:

**Node.js example**:

```javascript
const { DaprClient } = require('@dapr/dapr');
const client = new DaprClient();

// Get secret from Key Vault
const secret = await client.secret.get('secret-store', 'POSTGRES_CONNECTION_STRING');
console.log('Connection:', secret.POSTGRES_CONNECTION_STRING);
```

**Python example**:

```python
from dapr.clients import DaprClient

with DaprClient() as client:
    secret = client.get_secret('secret-store', 'POSTGRES_CONNECTION_STRING')
    print(f'Connection: {secret.secrets["POSTGRES_CONNECTION_STRING"]}')
```

### Environment Variables

Each Container App receives environment variables:

```yaml
env:
  - name: DAPR_HTTP_PORT
    value: '3500'
  - name: DAPR_GRPC_PORT
    value: '50001'
  - name: ENVIRONMENT
    value: 'dev'
  - name: LOG_LEVEL
    value: 'debug'
  - name: SERVICE_NAME
    value: 'product-service'
```

---

## Troubleshooting

### 1. OIDC Login Fails

**Error**: `AADSTS700016: Application with identifier 'xxx' was not found`

**Cause**: Federated credential not configured or subject mismatch.

**Solution**:

```bash
# List existing credentials
az ad app federated-credential list \
  --id $(az ad app list --display-name "xshopai-github-actions" --query "[0].id" -o tsv)

# Verify subject matches GitHub environment
# Expected: "environment:dev" or "environment:prod"
```

### 2. ACR Push Unauthorized

**Error**: `unauthorized: authentication required`

**Cause**: ACR admin user not enabled.

**Solution**:

```bash
az acr update --name xshopaimodulesdev --admin-enabled true
```

### 3. Container App Won't Start

**Symptoms**: App shows "Failed", continuous restarts.

**Diagnosis**:

```bash
# Check system logs (Dapr sidecar)
az containerapp logs show \
  --name product-service \
  --resource-group rg-xshopai-dev \
  --type system

# Check console logs (application)
az containerapp logs show \
  --name product-service \
  --resource-group rg-xshopai-dev \
  --type console
```

**Common causes**:

- Missing environment variables
- Health probe path incorrect (check `/health` endpoint)
- Database not accessible (check firewall rules)

### 4. Dapr Component Connection Issues

**Error**: `Error connecting to Dapr sidecar`

**Solution**:

```bash
# List Dapr components
az containerapp env dapr-component list \
  --name cae-xshopai-dev \
  --resource-group rg-xshopai-dev \
  --output table

# Verify Service Bus connection string in Key Vault
az keyvault secret show \
  --vault-name kv-xshopai-dev \
  --name servicebus-connection-string
```

### 5. Module Not Found in Registry

**Error**: `Module 'br:xshopaimodules.azurecr.io/bicep/container-apps/container-app:v1.0.0' not found`

**Solution**:

```bash
# Verify module exists
az acr repository list --name xshopaimodulesdev

# Re-publish if missing
gh workflow run publish-bicep-modules.yml \
  --field environment=dev \
  --field version=v1.0.0
```

### 6. Deployment Quota Exceeded

**Error**: `QuotaExceeded`

**Solution**:

```bash
# Check quotas
az vm list-usage --location swedencentral --output table

# Request increase via Azure Portal:
# Subscription → Usage + quotas → Request increase
```

---

## Cost Management

### Monthly Cost Estimate (Dev Environment)

| Resource        | SKU                        | Estimated Cost     |
| --------------- | -------------------------- | ------------------ |
| Container Apps  | Consumption (0-1 replicas) | $0-20              |
| ACR             | Premium                    | $40                |
| Cosmos DB       | Serverless                 | $0-25 (pay-per-RU) |
| PostgreSQL (3x) | Burstable B1ms             | $45 ($15 each)     |
| SQL Server      | Basic                      | $5                 |
| Redis           | Basic C0                   | $15                |
| Service Bus     | Basic                      | $0.05/million ops  |
| Key Vault       | Standard                   | $0.03/10k ops      |
| Log Analytics   | Pay-as-you-go              | $2-5               |
| **Total**       |                            | **$130-160/month** |

### Cost Optimization Tips

**Development**:

- ✅ Use consumption plan for Container Apps (scale to 0)
- ✅ Use Burstable SKUs for databases
- ✅ Use serverless Cosmos DB
- ✅ Set log retention to 7-14 days
- ✅ Delete unused Container App revisions

**Production**:

- Use reserved capacity for databases (1-3 year commitment)
- Enable autoscaling with min/max replicas
- Monitor costs via Azure Cost Management

### Cleanup Resources

```bash
# Delete entire resource group (⚠️ destroys everything)
az group delete --name rg-xshopai-dev --yes --no-wait

# Stop databases to reduce costs
az postgres flexible-server stop \
  --name psql-xshopai-product-dev \
  --resource-group rg-xshopai-dev
```

---

## Directory Structure

```
azure/container-apps/bicep/
├── bicepconfig.json              # ACR registry alias
├── README.md                     # This guide
├── modules/                      # 15 reusable modules
│   ├── acr.bicep
│   ├── container-app.bicep
│   ├── container-apps-environment.bicep
│   ├── cosmos-database.bicep
│   ├── key-vault.bicep
│   ├── key-vault-secrets.bicep
│   ├── log-analytics.bicep
│   ├── managed-identity.bicep
│   ├── mysql-database.bicep
│   ├── postgresql-database.bicep
│   ├── redis-cache.bicep
│   ├── resource-group.bicep
│   ├── service-bus.bicep
│   ├── sql-database.bicep
│   └── sql-server.bicep
└── environments/                 # Environment orchestration
    ├── dev/
    │   ├── main.bicep           # Dev orchestration
    │   └── main.bicepparam      # Dev parameters
    └── prod/
        ├── main.bicep           # Prod orchestration
        └── main.bicepparam      # Prod parameters
```

---

## Additional Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Dapr on Container Apps](https://learn.microsoft.com/azure/container-apps/dapr-overview)
- [GitHub Actions for Azure](https://learn.microsoft.com/azure/developer/github/github-actions)

---

## Support

For issues:

1. Check [Troubleshooting](#troubleshooting) section
2. Review GitHub Actions workflow logs
3. Check Azure Portal for resource health
4. Open issue in `xshopai/infrastructure` repository
