# Azure Container Apps - Bicep Deployment Architecture

Modular, reusable Bicep infrastructure for deploying xshopai microservices platform to Azure Container Apps with Dapr integration.

## 🎯 Architecture Overview

This deployment architecture follows a **modular, registry-based approach** with:

- **15 reusable Bicep modules** for infrastructure components
- **Environment-specific orchestration** (dev, prod) with parameter files
- **Azure Container Registry (ACR)** as module registry for versioning
- **Dapr integration** for pub/sub messaging, state management, and service invocation
- **Zero-downtime deployments** via GitHub Actions workflows

### Key Architectural Decisions

1. **Modular Design**: Each infrastructure component is a standalone module
2. **Registry Pattern**: Modules published to ACR for versioning and reuse
3. **Server-Only Pattern**: Databases deployed as servers; schemas managed via migrations
4. **Event-Driven**: Service Bus + Dapr pub/sub for async communication (9 topics)
5. **Security-First**: RBAC, managed identities, Key Vault integration, TLS 1.2+
6. **Observability**: Log Analytics workspace for monitoring and diagnostics

---

## 🚀 Getting Started: Complete Deployment Guide

This guide walks you through deploying the entire xshopai platform infrastructure from scratch, assuming you've cloned all repositories.

### Prerequisites

Before starting, ensure you have:

- **Azure Subscription** with Owner or Contributor access
- **Azure CLI** installed and authenticated (`az login`)
- **GitHub CLI** installed (`gh auth login`)
- **Git** for repository management
- **GitHub Organization**: `xshopai` (or your organization name)
- **Cloned Repositories**: All service repositories cloned locally

### Deployment Architecture

The deployment follows a **3-phase approach**:

```
Phase 1: Bootstrap Infrastructure
  └─ Creates ACR for hosting Bicep modules and container images

Phase 2: Platform Infrastructure  
  └─ Deploys 14 shared resources (databases, messaging, Key Vault, Container Apps Environment)

Phase 3: Service Deployment
  └─ Deploys 12 microservices as Container Apps
```

---

### 📋 Phase 0: Azure & GitHub Initial Setup (One-Time)

These steps configure **Azure OIDC (Federated Credentials)** for secure, password-less authentication between GitHub Actions and Azure.

#### Why OIDC Instead of Service Principal with Secrets?

**OIDC Approach** (Recommended - Used by our scripts):
- ✅ **No secrets to manage** - Uses federated credentials (no client secret!)
- ✅ **More secure** - Short-lived tokens issued per workflow run
- ✅ **No secret rotation** - Credentials don't expire
- ✅ **Simpler** - Only 3 GitHub secrets needed
- ✅ **Environment-based** - Only 2 credentials for ALL services (dev + prod)
- ✅ **Modern approach** - Industry best practice (Microsoft recommended)

**Service Principal with Secrets** (Older Approach - Don't use):
- ❌ Requires managing long-lived client secret
- ❌ Secret needs rotation (expires)
- ❌ 7+ GitHub secrets needed (including database passwords)
- ❌ Less secure (shared secret can be compromised)

---

#### Step 1: Authenticate GitHub CLI

First, ensure GitHub CLI is authenticated:

```bash
cd infrastructure/scripts/azure

# Authenticate GitHub CLI (if not already)
./gh-auth.sh
```

This will guide you through the GitHub authentication process.

#### Step 2: Set Up Azure OIDC (Federated Credentials)

Run the automated script to create Azure AD Application with OIDC:

```bash
# Still in infrastructure/scripts/azure directory
./setup-azure-oidc.sh
```

**This script will:**
1. ✅ Create Azure AD Application: `xshopai-github-actions`
2. ✅ Create Service Principal with roles:
   - Contributor (deploy resources)
   - User Access Administrator (manage identities)
   - AcrPush (push container images)
3. ✅ Configure all GitHub repos for environment-only OIDC
4. ✅ Create 2 federated credentials:
   - `xshopai-dev` → subject: `environment:dev`
   - `xshopai-prod` → subject: `environment:prod`
5. ✅ Display Azure values needed for GitHub secrets

**Key Benefits:**
- All services deploying to `dev` share ONE credential
- All services deploying to `prod` share ONE credential  
- No dependency on repository names or workflow filenames
- Can rename repos/workflows freely without breaking authentication

**Expected Output:**
```bash
============================================
✅ Azure OIDC Setup Complete!
============================================

📋 Summary:
   Azure AD Application: xshopai-github-actions
   Client ID: 12345678-1234-1234-1234-123456789abc
   Tenant ID: 11111111-1111-1111-1111-111111111111
   Subscription ID: 87654321-4321-4321-4321-cba987654321

🔐 GitHub Organization Secrets to Configure
============================================
Go to: https://github.com/organizations/xshopai/settings/secrets/actions

Add these secrets at the ORGANIZATION level:
   AZURE_CLIENT_ID       = 12345678-1234-1234-1234-123456789abc
   AZURE_TENANT_ID       = 11111111-1111-1111-1111-111111111111
   AZURE_SUBSCRIPTION_ID = 87654321-4321-4321-4321-cba987654321
```

#### Step 3: Configure GitHub Organization Secrets

Run the automated script to set GitHub secrets:

```bash
# Still in infrastructure/scripts/azure directory
./setup-github-secrets.sh
```

**This script will:**
1. ✅ Retrieve Client ID, Tenant ID, Subscription ID from Azure
2. ✅ Automatically set all 3 GitHub organization secrets
3. ✅ Verify secrets are configured correctly

**GitHub Secrets Created:**

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AZURE_CLIENT_ID` | From Azure AD App | Application (client) ID for OIDC |
| `AZURE_TENANT_ID` | From Azure | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | From Azure | Azure Subscription ID |

**That's it!** Only 3 secrets, no passwords needed at this stage.

**Note:** Database admin passwords are generated automatically during platform infrastructure deployment and stored securely in Azure Key Vault.

#### Step 4: Verify OIDC Setup

Verify the configuration:

```bash
# List GitHub organization secrets
gh secret list --org xshopai

# Expected output:
# AZURE_CLIENT_ID       Updated 2026-01-16
# AZURE_TENANT_ID       Updated 2026-01-16
# AZURE_SUBSCRIPTION_ID Updated 2026-01-16

# View Azure AD federated credentials
az ad app federated-credential list \
  --id $(az ad app list --display-name "xshopai-github-actions" --query "[0].id" -o tsv) \
  --query "[].{Name:name, Subject:subject}" \
  --output table

# Expected output:
# Name          Subject
# ------------  ----------------
# xshopai-dev   environment:dev
# xshopai-prod  environment:prod
```

#### Alternative: Manual OIDC Setup (If Scripts Fail)

If the automated scripts don't work, you can manually configure OIDC:

<details>
<summary>Click to expand manual steps</summary>

**1. Create Azure AD Application:**
```bash
APP_NAME="xshopai-github-actions"
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
echo "Client ID: $APP_ID"
```

**2. Create Service Principal:**
```bash
az ad sp create --id $APP_ID
SP_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Assign roles
az role assignment create --assignee $SP_ID --role "Contributor" --scope "/subscriptions/$(az account show --query id -o tsv)"
az role assignment create --assignee $SP_ID --role "User Access Administrator" --scope "/subscriptions/$(az account show --query id -o tsv)"
az role assignment create --assignee $SP_ID --role "AcrPush" --scope "/subscriptions/$(az account show --query id -o tsv)"
```

**3. Create Federated Credentials:**
```bash
APP_OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)
GITHUB_ORG="xshopai"

# Dev environment credential
az ad app federated-credential create \
  --id $APP_OBJECT_ID \
  --parameters '{
    "name": "xshopai-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "environment:dev",
    "description": "GitHub Actions OIDC for dev environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Prod environment credential
az ad app federated-credential create \
  --id $APP_OBJECT_ID \
  --parameters '{
    "name": "xshopai-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "environment:prod",
    "description": "GitHub Actions OIDC for prod environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**4. Set GitHub Secrets:**
```bash
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

gh secret set AZURE_CLIENT_ID --org xshopai --body "$APP_ID"
gh secret set AZURE_TENANT_ID --org xshopai --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --org xshopai --body "$SUBSCRIPTION_ID"
```

</details>

---

### 📋 Phase 1: Bootstrap Infrastructure (ACR Creation)

Bootstrap creates the Azure Container Registry that hosts Bicep modules.

#### Step 1: Navigate to Infrastructure Repository

```bash
cd infrastructure
```

#### Step 2: Validate Bootstrap Template

```bash
az bicep build --file azure/container-apps/bicep/dev/bootstrap/main.bicep
```

**Expected output:** ✅ Template validation succeeded

#### Step 3: Deploy Bootstrap via GitHub Actions

**Option A: Via GitHub UI**
1. Go to: https://github.com/xshopai/infrastructure/actions
2. Select workflow: "Deploy Bootstrap Infrastructure"
3. Click "Run workflow"
4. Parameters:
   - `environment`: **dev**
   - `location`: **swedencentral** (or your preferred region)
5. Click "Run workflow"

**Option B: Via GitHub CLI**
```bash
gh workflow run deploy-bootstrap-infrastructure.yml \
  --field environment=dev \
  --field location=swedencentral
```

#### Step 4: Verify Bootstrap Deployment

```bash
# Check if resource group was created
az group show --name rg-xshopai-bootstrap-dev

# Check if ACR was created
az acr show --name xshopaimodulesdev

# Verify you can log in to ACR
az acr login --name xshopaimodulesdev
```

**Expected Resources:**
- ✅ Resource Group: `rg-xshopai-bootstrap-dev`
- ✅ Azure Container Registry: `xshopaimodulesdev.azurecr.io`

---

### 📋 Phase 2: Publish Bicep Modules to ACR

Before deploying the platform, publish all reusable Bicep modules to the ACR.

#### Step 1: Run Publish Workflow

**Option A: Via GitHub UI**
1. Go to: https://github.com/xshopai/infrastructure/actions
2. Select workflow: "Publish Bicep Modules"
3. Click "Run workflow"
4. Parameters:
   - `environment`: **dev**
   - `version`: **v1.0.0**
5. Click "Run workflow"

**Option B: Via GitHub CLI**
```bash
gh workflow run publish-bicep-modules.yml \
  --field environment=dev \
  --field version=v1.0.0
```

#### Step 2: Verify Module Publishing

```bash
# List all published modules
az acr repository list \
  --name xshopaimodulesdev \
  --output table

# Expected 15 modules:
# - bicep/container-apps/acr
# - bicep/container-apps/container-app
# - bicep/container-apps/container-apps-environment
# - bicep/container-apps/cosmos-database
# - bicep/container-apps/key-vault
# - bicep/container-apps/log-analytics
# - bicep/container-apps/managed-identity
# - bicep/container-apps/mysql-database
# - bicep/container-apps/postgresql-database
# - bicep/container-apps/redis-cache
# - bicep/container-apps/resource-group
# - bicep/container-apps/service-bus
# - bicep/container-apps/sql-server
# - bicep/container-apps/sql-database
# - bicep/container-apps/key-vault-secrets

# Check a specific module version
az acr repository show-tags \
  --name xshopaimodulesdev \
  --repository bicep/container-apps/container-app
```

---

### 📋 Phase 3: Deploy Platform Infrastructure

Platform infrastructure includes databases, messaging, caching, and the Container Apps Environment.

#### Step 1: Review Platform Configuration

```bash
# Review parameter file
cat azure/container-apps/bicep/dev/platform/main.bicepparam

# Review what will be deployed
cat azure/container-apps/bicep/dev/platform/main.bicep | grep "^module"
```

#### Step 2: Run What-If Analysis (Dry Run)

```bash
gh workflow run deploy-platform-infrastructure.yml \
  --field environment=dev \
  --field location=swedencentral \
  --field dry_run=true
```

**Review the output** to see what resources will be created:
- ✅ Resource Group: `rg-xshopai-dev`
- ✅ Container Apps Environment
- ✅ Log Analytics Workspace
- ✅ Managed Identity
- ✅ Key Vault (with RBAC role assignment)
- ✅ PostgreSQL Servers (3): product, user, order
- ✅ Cosmos DB (MongoDB API)
- ✅ SQL Server + 2 databases (order, payment)
- ✅ MySQL Server (cart)
- ✅ Redis Cache
- ✅ Service Bus

**Total: ~14-17 resources**

#### Step 3: Deploy Platform (Actual Deployment)

```bash
gh workflow run deploy-platform-infrastructure.yml \
  --field environment=dev \
  --field location=swedencentral \
  --field dry_run=false
```

**⏱️ Expected duration:** 25-30 minutes (databases take time to provision)

#### Step 4: Monitor Deployment

**Option A: GitHub Actions UI**
1. Go to: https://github.com/xshopai/infrastructure/actions
2. Click on the running workflow
3. Monitor real-time logs

**Option B: Azure Portal**
1. Navigate to: https://portal.azure.com
2. Search for resource group: `rg-xshopai-dev`
3. Watch resources being created

#### Step 5: Verify Platform Deployment

```bash
# Check resource group
az group show --name rg-xshopai-dev

# List all resources in the group
az resource list \
  --resource-group rg-xshopai-dev \
  --output table

# Test Container Apps Environment
az containerapp env show \
  --name cae-xshopai-dev \
  --resource-group rg-xshopai-dev

# Test Key Vault access
az keyvault show \
  --name kv-xshopai-dev \
  --resource-group rg-xshopai-dev

# Verify database servers (examples)
az postgres flexible-server show \
  --name psql-xshopai-product-dev \
  --resource-group rg-xshopai-dev

az sql server show \
  --name sql-xshopai-dev \
  --resource-group rg-xshopai-dev
```

#### Step 6: Retrieve Platform Outputs

These values are needed for service deployments:

```bash
# Get deployment name (use latest)
DEPLOYMENT_NAME=$(az deployment sub list \
  --query "[?contains(name, 'platform-infra')].name | [0]" \
  --output tsv)

# Get all outputs
az deployment sub show \
  --name $DEPLOYMENT_NAME \
  --query properties.outputs \
  --output json > platform-outputs.json

# Key outputs to note:
# - containerAppsEnvironmentId
# - managedIdentityId  
# - managedIdentityPrincipalId
# - keyVaultName
# - keyVaultUri
# - postgresProductFqdn
# - postgresUserFqdn
# - postgresOrderFqdn
# - sqlServerFqdn
# - mysqlCartFqdn
# - redisHostname
# - serviceBusNamespace
```

---

### 📋 Phase 4: Deploy Microservices

Each microservice is deployed independently using its own deployment configuration.

#### Architecture

```
Each service repository contains:
├── .azure/
│   ├── deploy.bicep                    # Container App config
│   ├── deploy.parameters.dev.json      # Dev parameters
│   └── deploy.parameters.prod.json     # Prod parameters
├── .github/workflows/
│   ├── ci-build.yml                    # Build & test
│   └── cd-deploy.yml                   # Deploy to Container Apps
└── Dockerfile                          # Container image
```

#### Step 1: Deploy Individual Services

**Services to deploy (in recommended order):**

1. **Infrastructure Services** (no dependencies):
   ```bash
   # Deploy auth-service
   cd ../auth-service
   gh workflow run cd-deploy.yml --field environment=dev
   
   # Deploy user-service
   cd ../user-service
   gh workflow run cd-deploy.yml --field environment=dev
   ```

2. **Core Services**:
   ```bash
   # Deploy product-service
   cd ../product-service
   gh workflow run cd-deploy.yml --field environment=dev
   
   # Deploy inventory-service
   cd ../inventory-service
   gh workflow run cd-deploy.yml --field environment=dev
   
   # Deploy cart-service
   cd ../cart-service
   gh workflow run cd-deploy.yml --field environment=dev
   ```

3. **Business Services**:
   ```bash
   # Deploy order-service
   cd ../order-service
   gh workflow run cd-deploy.yml --field environment=dev
   
   # Deploy payment-service
   cd ../payment-service
   gh workflow run cd-deploy.yml --field environment=dev
   
   # Deploy review-service
   cd ../review-service
   gh workflow run cd-deploy.yml --field environment=dev
   ```

4. **Supporting Services**:
   ```bash
   # Deploy notification-service
   cd ../notification-service
   gh workflow run cd-deploy.yml --field environment=dev
   
   # Deploy audit-service
   cd ../audit-service
   gh workflow run cd-deploy.yml --field environment=dev
   ```

5. **API Gateway**:
   ```bash
   # Deploy web-bff
   cd ../web-bff
   gh workflow run cd-deploy.yml --field environment=dev
   ```

#### Step 2: Verify Service Deployments

```bash
# List all container apps
az containerapp list \
  --resource-group rg-xshopai-dev \
  --output table

# Check specific service status
az containerapp show \
  --name product-service \
  --resource-group rg-xshopai-dev \
  --query "properties.{fqdn:configuration.ingress.fqdn,replicas:template.scale.maxReplicas,health:runningStatus}" \
  --output table

# Test service health endpoint
curl https://product-service.${CONTAINER_ENV_DOMAIN}/health
```

#### Step 3: Initialize Databases

Each service needs to create its application database and user:

**Example for product-service (PostgreSQL):**
```bash
# Connect to PostgreSQL admin
PGHOST=$(az postgres flexible-server show \
  --name psql-xshopai-product-dev \
  --resource-group rg-xshopai-dev \
  --query fullyQualifiedDomainName -o tsv)

# Run database initialization (in service deployment workflow)
psql -h $PGHOST -U postgresadmin -d postgres << EOF
CREATE DATABASE IF NOT EXISTS productdb;
CREATE USER IF NOT EXISTS productapp WITH PASSWORD '${PRODUCT_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE productdb TO productapp;
EOF

# Store app connection string in Key Vault
az keyvault secret set \
  --vault-name kv-xshopai-dev \
  --name product-db-connection-string \
  --value "Host=$PGHOST;Database=productdb;Username=productapp;Password=${PRODUCT_DB_PASSWORD}"
```

**This step is typically automated in each service's deployment workflow.**

---

### 📋 Post-Deployment Configuration

#### Step 1: Configure Custom Domains (Optional)

```bash
# Add custom domain to Container Apps Environment
az containerapp env certificate upload \
  --name cae-xshopai-dev \
  --resource-group rg-xshopai-dev \
  --certificate-file ./ssl-cert.pfx \
  --password <cert-password>

# Bind custom domain to service
az containerapp hostname add \
  --name product-service \
  --resource-group rg-xshopai-dev \
  --hostname api.xshopai.com
```

#### Step 2: Configure Monitoring Alerts

```bash
# Create alert for service health
az monitor metrics alert create \
  --name "product-service-availability" \
  --resource-group rg-xshopai-dev \
  --scopes $(az containerapp show --name product-service --resource-group rg-xshopai-dev --query id -o tsv) \
  --condition "avg Percentage CPU > 80" \
  --description "Alert when CPU exceeds 80%" \
  --evaluation-frequency 5m \
  --window-size 15m \
  --action <action-group-id>
```

#### Step 3: Review Costs

```bash
# View cost analysis for dev environment
az consumption usage list \
  --start-date $(date -d '30 days ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName, 'xshopai-dev')]" \
  --output table

# Expected monthly cost (dev environment): $350-450 USD
```

---

### 🔍 Troubleshooting Common Issues

#### Issue 1: "Module not found in registry"

**Error:** `Module 'br:xshopaimodulesdev.azurecr.io/bicep/container-apps/container-app:v1.0.0' not found`

**Solution:**
```bash
# Verify module was published
az acr repository list --name xshopaimodulesdev

# Re-publish modules
gh workflow run publish-bicep-modules.yml --field environment=dev --field version=v1.0.0
```

#### Issue 2: "Insufficient permissions"

**Error:** `The client '...' does not have authorization to perform action 'Microsoft.Resources/deployments/write'`

**Solution:**
```bash
# Grant Contributor role to Service Principal
az role assignment create \
  --assignee <AZURE_CLIENT_ID> \
  --role "Contributor" \
  --scope "/subscriptions/<AZURE_SUBSCRIPTION_ID>"
```

#### Issue 3: "Key Vault access denied"

**Error:** `The user, group or application does not have secrets get permission`

**Solution:**
```bash
# Verify RBAC role assignment exists
az role assignment list \
  --scope $(az keyvault show --name kv-xshopai-dev --query id -o tsv) \
  --output table

# If missing, redeploy platform to create role assignment
gh workflow run deploy-platform-infrastructure.yml --field environment=dev --field dry_run=false
```

#### Issue 4: "Database connection failed"

**Error:** Container app logs show database connection errors

**Solution:**
```bash
# 1. Verify database server is running
az postgres flexible-server show --name psql-xshopai-product-dev --resource-group rg-xshopai-dev

# 2. Check firewall rules allow Container Apps subnet
az postgres flexible-server firewall-rule list \
  --resource-group rg-xshopai-dev \
  --server-name psql-xshopai-product-dev

# 3. Verify connection string in Key Vault
az keyvault secret show \
  --vault-name kv-xshopai-dev \
  --name product-db-connection-string
```

---

### 📊 Deployment Summary

After completing all phases, you should have:

| Resource Type | Count | Status |
|--------------|-------|--------|
| **Resource Groups** | 2 | ✅ bootstrap-dev, dev |
| **Azure Container Registry** | 1 | ✅ Hosts modules + images |
| **Container Apps Environment** | 1 | ✅ Hosts all microservices |
| **Container Apps** | 12 | ✅ All microservices deployed |
| **PostgreSQL Servers** | 3 | ✅ product, user, order |
| **SQL Server + Databases** | 3 | ✅ Server + 2 databases |
| **MySQL Server** | 1 | ✅ cart database |
| **Cosmos DB** | 1 | ✅ MongoDB API |
| **Redis Cache** | 1 | ✅ Session + state |
| **Service Bus** | 1 | ✅ 9 topics configured |
| **Key Vault** | 1 | ✅ Secrets + RBAC configured |
| **Managed Identity** | 1 | ✅ With Key Vault access |
| **Log Analytics** | 1 | ✅ Centralized logging |

**Total Azure Resources:** ~30-35 resources

**Monthly Cost Estimate (Dev):** $350-450 USD

---

### 🔗 Next Steps

1. **Configure CI/CD Pipelines**: Set up automated deployments for all services
2. **Set Up Monitoring**: Create dashboards in Azure Monitor
3. **Configure Alerts**: Set up notifications for critical metrics
4. **Load Testing**: Test platform under expected load
5. **Security Review**: Run Azure Security Center recommendations
6. **Documentation**: Document service endpoints and API contracts
7. **Production Deployment**: Repeat process for production environment with higher SKUs

---

### 📚 Additional Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Dapr on Container Apps](https://learn.microsoft.com/azure/container-apps/dapr-overview)
- [GitHub Actions for Azure](https://learn.microsoft.com/azure/developer/github/github-actions)
- [Azure Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/)

## 📁 Directory Structure

```
azure/container-apps/bicep/
├── bicepconfig.json              # ACR registry alias configuration
├── README.md                     # This comprehensive documentation
├── bicep-registry/               # ACR infrastructure deployment
│   ├── main.bicep               # Deploys ACR for module registry
│   └── README.md                # Registry setup guide
├── modules/                      # 15 reusable Bicep modules (all validated ✅)
│   ├── acr.bicep                           # Azure Container Registry
│   ├── container-app.bicep                 # Individual microservice deployment
│   ├── container-apps-environment.bicep    # Managed environment (hosting platform)
│   ├── cosmos-database.bicep               # Cosmos DB NoSQL database
│   ├── dapr-components.bicep               # 5 Dapr components configuration
│   ├── key-vault.bicep                     # Azure Key Vault for secrets
│   ├── key-vault-secrets.bicep             # Bulk secret creation
│   ├── log-analytics.bicep                 # Log Analytics workspace
│   ├── managed-identity.bicep              # User-assigned managed identity
│   ├── mysql-database.bicep                # MySQL Flexible Server
│   ├── postgresql-database.bicep           # PostgreSQL Flexible Server
│   ├── redis.bicep                         # Azure Cache for Redis
│   ├── resource-group.bicep                # Subscription-scope resource group
│   ├── service-bus.bicep                   # Service Bus with 9 topics + RBAC
│   └── sql-server.bicep                    # SQL Server with Key Vault integration
└── environments/                 # Environment orchestration (TO BE CREATED)
    ├── dev/
    │   ├── main.bicep           # Dev orchestration (references all modules)
    │   └── main.bicepparam      # Dev-specific parameters
    └── prod/
        └── main.bicepparam      # Prod-specific parameters (higher SKUs)
```

## �️ Module Catalog (15 Modules - All Validated ✅)

### 1. Resource Group & Foundational Infrastructure

#### `resource-group.bicep`
- **Purpose**: Subscription-scope resource group creation
- **Parameters**: `name`, `location` (20+ allowed locations, default: swedencentral)
- **Outputs**: `id`, `name`, `location`
- **Use Case**: First deployment step for any environment

#### `log-analytics.bicep`
- **Purpose**: Central monitoring and diagnostics workspace
- **Parameters**: `name`, `location`, `retentionInDays` (30-730), `sku` (PerGB2018)
- **Outputs**: `workspaceId`, `workspaceName`, `customerId`, `primarySharedKey`
- **Integration**: Required by `container-apps-environment.bicep`

#### `managed-identity.bicep`
- **Purpose**: User-assigned managed identity for services
- **Parameters**: `name`, `location`, `tags`
- **Outputs**: `id`, `principalId`, `clientId`, `name`
- **Integration**: 
  - `principalId` → Service Bus RBAC role assignment
  - `clientId` → Dapr Key Vault component authentication

#### `acr.bicep`
- **Purpose**: Container registry for Docker images and Bicep modules
- **Parameters**: `name`, `location`, `sku` (Basic/Standard/Premium), `adminUserEnabled` (false)
- **Outputs**: `name`, `loginServer`, `resourceId`
- **Use Case**: Hosts both container images AND published Bicep modules

### 2. Container Apps Platform

#### `container-apps-environment.bicep` ⭐ Core Platform
- **Purpose**: Managed environment hosting all microservices
- **Parameters**: 
  - `name`, `location`
  - `logAnalyticsWorkspaceId` (required)
  - `internalOnly` (false), `zoneRedundant` (false)
- **Features**:
  - Integrates Log Analytics via `reference()` and `listKeys()`
  - Supports VNet internal-only mode
  - Zone redundancy for high availability
- **Outputs**: `name`, `resourceId`, `defaultDomain`, `staticIp`
- **Integration**: 
  - Input: `logAnalyticsWorkspaceId` from `log-analytics.bicep`
  - Output: `resourceId` consumed by `container-app.bicep` and `dapr-components.bicep`

#### `container-app.bicep` ⭐ Microservice Deployment
- **Purpose**: Deploy individual microservice with auto-scaling and health probes
- **Parameters** (15 total):
  - Core: `name`, `location`, `environmentId`, `containerImage`
  - Resources: `cpu` (0.25-4.0), `memory` (0.5Gi-8Gi)
  - Networking: `targetPort`, `externalIngress`, `allowInsecure`
  - Scaling: `minReplicas` (0), `maxReplicas` (30)
  - Configuration: `envVars`, `secrets`, `healthProbePath`
  - Dapr: `daprEnabled`, `daprAppId`, `daprAppPort`
- **Features**:
  - Auto-scaling: 0-30 replicas based on HTTP traffic
  - Health probes: Liveness (startup + ongoing) and readiness
  - Dapr sidecar: Optional integration for service mesh
  - Registry authentication: ACR integration
  - Secret management: Secure environment variables
- **Outputs**: `name`, `fqdn`, `url`, `resourceId`, `latestRevisionName`
- **Integration**: 
  - Requires `environmentId` from `container-apps-environment.bicep`
  - Optional managed identity for ACR authentication

### 3. Dapr Components

#### `dapr-components.bicep` ⭐ Service Mesh Configuration
- **Purpose**: Configure 5 Dapr components for service-to-service communication
- **Parameters**: 
  - `containerAppsEnvName` (parent environment name)
  - `serviceBusConnectionString`, `redisHost`, `redisPassword`
  - `keyVaultName`, `managedIdentityClientId`
- **Components Created**:

1. **pubsub** (Service Bus Topics)
   - Type: `pubsub.azure.servicebus`
   - Backend: Service Bus Topics (not queues)
   - Scoped to: 12 services (user, product, order, payment, inventory, notification, cart, review, audit, auth, admin, order-processor)
   - Topics: 9 pre-created topics (user-events, product-events, etc.)

2. **statestore** (Redis)
   - Type: `state.redis`
   - Backend: Azure Cache for Redis
   - Scoped to: 5 services (user, product, order, cart, auth)
   - Use Case: Session state, shopping cart persistence

3. **cosmos-binding** (Cosmos DB)
   - Type: `bindings.azure.cosmosdb`
   - Backend: Cosmos DB (MongoDB/SQL API)
   - Scoped to: audit-service only
   - Use Case: Audit log storage with change feed

4. **secret-store** (Key Vault)
   - Type: `secretstores.azure.keyvault`
   - Backend: Azure Key Vault
   - Authentication: Managed Identity (clientId)
   - Scoped to: 13 apps (12 services + web-bff)
   - Use Case: Runtime secret retrieval

5. **configstore** (Redis)
   - Type: `configuration.redis`
   - Backend: Azure Cache for Redis
   - Scoped to: 2 services (web-bff, admin)
   - Use Case: Dynamic configuration management

- **Integration**:
  - Depends on: `container-apps-environment`, `service-bus`, `redis`, `key-vault`, `managed-identity`, `cosmos-database`
  - Secret references: Uses `secretRef` pattern for sensitive data

### 4. Messaging & Eventing

#### `service-bus.bicep` ⭐ Message Broker
- **Purpose**: Async pub/sub messaging backbone for event-driven architecture
- **Parameters**: `namespaceName`, `location`, `sku` (Standard), `managedIdentityPrincipalId`
- **Resources Created**:
  - **Namespace**: Service Bus namespace (Standard SKU for topics)
  - **9 Topics**: Pre-created with default settings
    - `user-events` - User registration, profile updates
    - `product-events` - Product catalog changes
    - `order-events` - Order lifecycle events
    - `payment-events` - Payment processing events
    - `inventory-events` - Stock level changes
    - `notification-events` - Notification triggers
    - `cart-events` - Cart operations
    - `review-events` - Product reviews
    - `audit-events` - Audit trail events
  - **RBAC Role Assignment**: Azure Service Bus Data Owner to managed identity
- **Outputs**: `id`, `namespaceName`, `connectionString`, `endpoint`
- **Security**: RBAC-based access (no shared access keys in Dapr components)

### 5. Data Storage

#### `redis.bicep`
- **Purpose**: In-memory cache for state and configuration
- **Parameters**: `name`, `location`, `sku` (Basic/Standard/Premium), `capacity` (0-6)
- **Security**: 
  - `enableNonSslPort: false` (TLS required)
  - `minimumTlsVersion: '1.2'`
- **Outputs**: `id`, `name`, `hostName`, `sslPort`, `primaryKey`, `connectionString`
- **Integration**: Used by `dapr-components.bicep` (statestore + configstore)

#### `cosmos-database.bicep`
- **Purpose**: NoSQL database for audit logs and flexible schema data
- **Parameters**: `name`, `location`, `apiType` (MongoDB/Sql/Cassandra/Gremlin/Table), `serverless` (false)
- **Outputs**: `connectionString`, `resourceId`
- **Integration**: Used by `dapr-components.bicep` (cosmos-binding)

#### `sql-server.bicep` ⭐ SQL Database Server
- **Purpose**: Relational database server with Key Vault integration
- **Parameters**: 
  - `location`, `baseName`, `administratorLogin`, `administratorLoginPassword`
  - `publicNetworkAccess` (Enabled/Disabled), `allowedIpAddresses` (array)
  - `keyVaultName` (for secret storage)
  - `azureAdAdminObjectId`, `azureAdOnlyAuthentication` (false)
- **Resources Created**:
  - SQL Server with Azure AD admin
  - Firewall rules for allowed IPs
  - Allow Azure Services rule
  - 3 Key Vault secrets: admin-login, admin-password, server-fqdn
- **Pattern**: Server-only deployment (databases created via migrations)
- **Outputs**: `serverName`, `serverFqdn`, `serverId`, `connectionStringTemplate`
- **Security**: Azure AD authentication, Key Vault secret storage

#### `mysql-database.bicep`
- **Purpose**: MySQL Flexible Server
- **Parameters**: `serverName`, `location`, `administratorLogin`, `administratorLoginPassword`, `sku` (Burstable/GeneralPurpose/MemoryOptimized), `version` (5.7/8.0)
- **Pattern**: Server-only deployment (databases via migrations)
- **Outputs**: `serverName`, `serverFqdn`, `serverId`, `connectionStringTemplate`

#### `postgresql-database.bicep`
- **Purpose**: PostgreSQL Flexible Server
- **Parameters**: `serverName`, `location`, `administratorLogin`, `administratorLoginPassword`, `sku`, `version` (11/12/13/14/15)
- **Pattern**: Server-only deployment (databases via migrations)
- **Outputs**: `serverName`, `serverFqdn`, `serverId`, `connectionStringTemplate`

### 6. Security & Secrets

#### `key-vault.bicep` ⭐ Secrets Management
- **Purpose**: Centralized secrets storage for all services
- **Parameters**: 
  - `name`, `location`, `sku` (Standard/Premium)
  - `enableSoftDelete` (true, 90-day retention)
  - `enablePurgeProtection` (true)
  - `enableRbacAuthorization` (true)
- **Security Features**:
  - Soft delete with 90-day recovery window
  - Purge protection (cannot permanently delete)
  - RBAC-based access (no access policies)
- **Outputs**: `name`, `uri`, `resourceId`
- **Integration**: 
  - Used by `key-vault-secrets.bicep` for bulk secret creation
  - Used by `sql-server.bicep` for storing DB credentials
  - Used by `dapr-components.bicep` (secret-store component)

#### `key-vault-secrets.bicep`
- **Purpose**: Bulk secret creation in Key Vault
- **Parameters**: 
  - `keyVaultName` (existing Key Vault)
  - `secrets` (array of {name, value} objects)
- **Outputs**: `secretNames` (array), `secretCount`
- **Use Case**: Batch secret deployment for multiple services
---

## 🚀 Application Deployment Pattern

### Separation of Concerns

This repository contains **platform infrastructure** (Container Apps Environment, databases, Service Bus, etc.). Each **microservice** (like `product-service`) maintains its own deployment configuration in its service folder.

```
📦 Repository Structure
├── infrastructure/azure/container-apps/bicep/    # ← Platform Infrastructure (THIS REPO)
│   ├── modules/                                   # 15 reusable Bicep modules
│   ├── environments/                              # Platform orchestration (dev/prod)
│   └── README.md                                  # This file
│
├── product-service/                               # ← Application Code + Deployment
│   ├── src/                                       # Python/FastAPI application code
│   ├── tests/                                     # Unit/integration tests
│   ├── Dockerfile                                 # Container image definition
│   ├── .azure/                                    # 🔥 Application deployment config
│   │   ├── deploy.bicep                           # References infrastructure modules
│   │   ├── deploy.parameters.dev.json             # Dev-specific app config
│   │   └── deploy.parameters.prod.json            # Prod-specific app config
│   └── .github/workflows/
│       ├── ci-build.yml                           # Build & test on PR
│       └── cd-deploy.yml                          # Deploy to Container Apps
│
├── user-service/                                  # Another microservice
│   ├── src/
│   ├── .azure/                                    # 🔥 Its own deployment config
│   └── .github/workflows/
│
└── (other services...)
```

### Example: Product Service Deployment

#### `product-service/.azure/deploy.bicep`
```bicep
// Product Service deployment configuration
// References base infrastructure modules from the platform repository

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS - Service-specific configuration
// ============================================================================

@description('Environment name (dev, staging, prod)')
param environment string

@description('Product service container image (with tag)')
param containerImage string

@description('Container Apps Environment resource ID (from platform deployment)')
param containerAppsEnvironmentId string

@description('Container Apps Environment name')
param containerAppsEnvironmentName string

@description('Managed Identity Client ID (for Key Vault access)')
param managedIdentityClientId string

@description('Key Vault name for secrets')
param keyVaultName string

@description('Location for resources')
param location string = resourceGroup().location

// ============================================================================
// MODULE REFERENCE - Use infrastructure modules from ACR
// ============================================================================

module productServiceApp 'br/xshopai:container-app:v1.0.0' = {
  name: 'product-service-app'
  params: {
    name: 'product-service'
    location: location
    environmentId: containerAppsEnvironmentId
    containerImage: containerImage
    targetPort: 8001
    cpu: '1.0'
    memory: '2Gi'
    minReplicas: 1
    maxReplicas: 10
    externalIngress: true
    allowInsecure: false
    
    // Dapr configuration
    daprEnabled: true
    daprAppId: 'product-service'
    daprAppPort: 8001
    
    // Environment variables
    envVars: [
      {
        name: 'ENVIRONMENT'
        value: environment
      }
      {
        name: 'SERVICE_NAME'
        value: 'product-service'
      }
      {
        name: 'SERVICE_PORT'
        value: '8001'
      }
      {
        name: 'DAPR_HTTP_PORT'
        value: '3501'
      }
      {
        name: 'DAPR_GRPC_PORT'
        value: '50001'
      }
      {
        name: 'LOG_LEVEL'
        value: environment == 'prod' ? 'info' : 'debug'
      }
      // Key Vault reference (runtime secrets via Dapr secret-store)
      {
        name: 'KEY_VAULT_NAME'
        value: keyVaultName
      }
      {
        name: 'MANAGED_IDENTITY_CLIENT_ID'
        value: managedIdentityClientId
      }
    ]
    
    // Secrets (sensitive configuration)
    secrets: [
      {
        name: 'mongodb-connection-string'
        keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/product-mongodb-connection-string'
        identity: managedIdentityClientId
      }
    ]
    
    // Health probe configuration
    healthProbePath: '/health'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output productServiceUrl string = productServiceApp.outputs.url
output productServiceFqdn string = productServiceApp.outputs.fqdn
output latestRevision string = productServiceApp.outputs.latestRevisionName
```

#### `product-service/.azure/deploy.parameters.dev.json`
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environment": {
      "value": "dev"
    },
    "containerImage": {
      "value": "xshopaimodules.azurecr.io/product-service:${BUILD_TAG}"
    },
    "containerAppsEnvironmentId": {
      "reference": {
        "keyVault": {
          "id": "/subscriptions/{subscription-id}/resourceGroups/xshopai-dev-rg/providers/Microsoft.KeyVault/vaults/xshopai-dev-kv"
        },
        "secretName": "container-apps-environment-id"
      }
    },
    "containerAppsEnvironmentName": {
      "value": "xshopai-dev-env"
    },
    "managedIdentityClientId": {
      "reference": {
        "keyVault": {
          "id": "/subscriptions/{subscription-id}/resourceGroups/xshopai-dev-rg/providers/Microsoft.KeyVault/vaults/xshopai-dev-kv"
        },
        "secretName": "managed-identity-client-id"
      }
    },
    "keyVaultName": {
      "value": "xshopai-dev-kv"
    }
  }
}
```

#### `product-service/.github/workflows/cd-deploy.yml`
```yaml
name: Deploy Product Service

on:
  push:
    branches: [main]
    paths:
      - 'product-service/**'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - prod

env:
  ACR_NAME: xshopaimodules
  SERVICE_NAME: product-service

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    
    steps:
      # 1. Build and push container image
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Log in to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Log in to ACR
        run: az acr login --name ${{ env.ACR_NAME }}
      
      - name: Build and push Docker image
        working-directory: ./product-service
        run: |
          IMAGE_TAG="${{ github.sha }}"
          docker build -t ${{ env.ACR_NAME }}.azurecr.io/${{ env.SERVICE_NAME }}:${IMAGE_TAG} .
          docker push ${{ env.ACR_NAME }}.azurecr.io/${{ env.SERVICE_NAME }}:${IMAGE_TAG}
          echo "IMAGE_TAG=${IMAGE_TAG}" >> $GITHUB_ENV
      
      # 2. Deploy to Container Apps using Bicep
      - name: Deploy to Container Apps
        uses: azure/arm-deploy@v2
        with:
          subscriptionId: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          resourceGroupName: xshopai-${{ inputs.environment }}-rg
          template: ./product-service/.azure/deploy.bicep
          parameters: >
            ./product-service/.azure/deploy.parameters.${{ inputs.environment }}.json
            containerImage=${{ env.ACR_NAME }}.azurecr.io/${{ env.SERVICE_NAME }}:${{ env.IMAGE_TAG }}
          deploymentName: deploy-product-service-${{ github.run_number }}
      
      # 3. Verify deployment
      - name: Get deployment outputs
        id: deployment
        run: |
          DEPLOYMENT_NAME="deploy-product-service-${{ github.run_number }}"
          PRODUCT_URL=$(az deployment group show \
            --resource-group xshopai-${{ inputs.environment }}-rg \
            --name $DEPLOYMENT_NAME \
            --query properties.outputs.productServiceUrl.value -o tsv)
          echo "Product Service URL: $PRODUCT_URL"
          echo "url=$PRODUCT_URL" >> $GITHUB_OUTPUT
      
      - name: Health check
        run: |
          echo "Waiting 30 seconds for service to start..."
          sleep 30
          curl -f ${{ steps.deployment.outputs.url }}/health || exit 1
          echo "✅ Health check passed!"
```

### Key Points

#### 1. **Infrastructure vs. Application Deployment**

| Concern | Location | Responsibility | Examples |
|---------|----------|----------------|----------|
| **Platform Infrastructure** | `infrastructure/azure/container-apps/bicep/` | Platform team | Container Apps Environment, Service Bus, databases, Key Vault, ACR |
| **Application Deployment** | `{service}/.azure/` | Service team | Container App configuration, environment variables, scaling rules |

#### 2. **Module References**

Applications reference infrastructure modules from ACR:
```bicep
// ✅ DO THIS (Production pattern)
module productServiceApp 'br/xshopai:container-app:v1.0.0' = { ... }

// ❌ DON'T DO THIS (Tight coupling)
module productServiceApp '../../../../infrastructure/azure/container-apps/bicep/modules/container-app.bicep' = { ... }
```

#### 3. **Deployment Order**

1. **Platform Infrastructure** (One-time setup per environment)
   ```bash
   # Deploy platform infrastructure (Container Apps Environment, databases, etc.)
   gh workflow run deploy-container-apps.yml --field environment=dev
   ```

2. **Application Deployment** (Per service, on every release)
   ```bash
   # Build and deploy product-service
   gh workflow run product-service/cd-deploy.yml --field environment=dev
   
   # Build and deploy user-service
   gh workflow run user-service/cd-deploy.yml --field environment=dev
   
   # ... (repeat for all 12 services)
   ```

#### 4. **Required Infrastructure Outputs**

Each service deployment needs these values from platform infrastructure:

- **Container Apps Environment ID**: `containerAppsEnvironmentId`
- **Managed Identity Client ID**: `managedIdentityClientId`
- **Key Vault Name**: `keyVaultName`
- **ACR Name**: `acrName`

**Best Practice**: Store these in Key Vault and reference them in parameter files.

#### 5. **Service-Specific Configuration**

Each service folder (`product-service/`, `user-service/`, etc.) should contain:

```
{service-name}/
├── .azure/
│   ├── deploy.bicep                    # Container App deployment
│   ├── deploy.parameters.dev.json      # Dev configuration
│   └── deploy.parameters.prod.json     # Prod configuration
├── .github/workflows/
│   ├── ci-build.yml                    # Build & test
│   └── cd-deploy.yml                   # Deploy to Azure
├── Dockerfile                          # Container image
├── src/                                # Application code
└── tests/                              # Tests
```

### Next Steps for Application Deployments

After completing the platform infrastructure deployment:

1. **Create `.azure/` folder in each service** (12 services)
2. **Create `deploy.bicep`** for each service (reference the example above)
3. **Create parameter files** for dev and prod
4. **Create GitHub workflows** for CI/CD
5. **Deploy services incrementally** (one at a time, test each)

**Example Services**:
- `product-service` (Python/FastAPI - shown above)
- `user-service` (Node.js/Express)
- `order-service` (.NET/C#)
- `cart-service` (Java/Spring Boot)
- ... (8 more services)

---
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
