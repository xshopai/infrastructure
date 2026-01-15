# Azure Container Apps Deployment Guide

Complete guide for deploying the xshopai platform to Azure Container Apps from scratch.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Setup](#detailed-setup)
   - [Step 1: Azure Account Setup](#step-1-azure-account-setup)
   - [Step 2: Azure AD Application & OIDC](#step-2-azure-ad-application--oidc)
   - [Step 3: GitHub Configuration](#step-3-github-configuration)
   - [Step 4: Infrastructure Deployment](#step-4-infrastructure-deployment)
   - [Step 5: Post-Deployment Configuration](#step-5-post-deployment-configuration)
   - [Step 6: Service Deployment](#step-6-service-deployment)
4. [Architecture Overview](#architecture-overview)
5. [Resource Naming Convention](#resource-naming-convention)
6. [Environment Configuration](#environment-configuration)
7. [Troubleshooting](#troubleshooting)
8. [Cost Management](#cost-management)

---

## Prerequisites

### Software Requirements

| Tool | Version | Installation |
|------|---------|--------------|
| Azure CLI | 2.50+ | `winget install Microsoft.AzureCLI` |
| Git | 2.40+ | `winget install Git.Git` |
| Node.js | 18+ | `winget install OpenJS.NodeJS.LTS` |
| Docker Desktop | Latest | [Download](https://www.docker.com/products/docker-desktop/) |

### Azure Requirements

- Azure subscription with **Contributor** access
- Ability to create Azure AD applications (requires Azure AD admin or Application Administrator role)
- Sufficient quota for:
  - Container Apps
  - Azure Container Registry
  - Cosmos DB
  - PostgreSQL Flexible Server
  - Redis Cache
  - Service Bus

### GitHub Requirements

- GitHub organization: `xshopai`
- Admin access to the organization
- All repositories cloned locally

---

## Quick Start

For experienced users, here's the condensed version:

```bash
# 1. Clone infrastructure repo
git clone https://github.com/xshopai/infrastructure.git
cd infrastructure

# 2. Login to Azure
az login
az account set --subscription <your-subscription-id>

# 3. Run OIDC setup script
./scripts/azure/setup-azure-oidc.sh

# 4. Configure GitHub org secrets (automated)
gh auth login
./scripts/azure/setup-github-secrets.sh

# 5. Run infrastructure deployment via GitHub Actions
#    Go to: Actions → "Deploy Azure Container Apps (Layered)" → Run workflow
#    Select: environment=dev, layers=all

# 6. Run post-deployment config
./scripts/azure/post-deploy-config.sh dev

# 7. Deploy services via their GitHub Actions workflows
```

---

## Detailed Setup

### Step 1: Azure Account Setup

#### 1.1 Login to Azure

```bash
# Interactive login
az login

# List available subscriptions
az account list --output table

# Set the subscription to use
az account set --subscription "<subscription-name-or-id>"

# Verify current context
az account show
```

#### 1.2 Register Required Resource Providers

```bash
# Register providers (run once per subscription)
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.Cache
az provider register --namespace Microsoft.ServiceBus
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ManagedIdentity

# Verify registration status
az provider show --namespace Microsoft.App --query "registrationState"
```

#### 1.3 Verify Quotas

```bash
# Check VM quotas (Container Apps uses VMs internally)
az vm list-usage --location swedencentral --output table

# If you hit quota limits, request increase via Azure Portal
```

---

### Step 2: Azure AD Application & OIDC

GitHub Actions uses OpenID Connect (OIDC) to authenticate with Azure without storing secrets. This is more secure than using service principal credentials.

#### Understanding the Two-Identity Architecture

The xshopai platform uses **two different identities** for different purposes:

| Identity | Purpose | Used By | How It Authenticates |
|----------|---------|---------|---------------------|
| **Azure AD App** (`xshopai-github-actions`) | External identity for GitHub Actions to deploy TO Azure | GitHub Actions workflows | OIDC (passwordless via federated credentials) |
| **Managed Identity** (`id-xshopai-dev`) | Azure-native identity for running containers to access Azure resources | Container Apps at runtime | Automatic (Azure handles internally) |

**Why two identities?**

1. **Azure AD App** - GitHub is EXTERNAL to Azure. GitHub needs to prove its identity to Azure before it can deploy resources. This is done via OIDC tokens that Azure validates against federated credentials.

2. **Managed Identity** - Once containers are running INSIDE Azure, they use Managed Identity. Azure automatically injects tokens - no credentials needed in code. Dapr sidecars use this identity to access Key Vault, Service Bus, etc.

```
GitHub Actions                          Azure
┌─────────────────┐                    ┌─────────────────────────────────────┐
│ Workflow runs   │    OIDC Token      │  Azure AD validates against         │
│ Requests ID     │ ─────────────────► │  Federated Credential config        │
│ token from GH   │                    │                                     │
│                 │ ◄───────────────── │  Returns Azure Access Token         │
│                 │   Access Token     │                                     │
│                 │                    │                                     │
│ Uses token to   │ ─────────────────► │  Deploys Container App              │
│ deploy          │   az login         │                                     │
└─────────────────┘                    │                                     │
                                       │  ┌─────────────────────────────────┐│
                                       │  │ Container App (running)         ││
                                       │  │                                 ││
                                       │  │ Uses Managed Identity           ││
                                       │  │ (id-xshopai-dev) to access:     ││
                                       │  │ - Key Vault secrets             ││
                                       │  │ - Service Bus pub/sub           ││
                                       │  │ - Redis cache                   ││
                                       │  │                                 ││
                                       │  │ (Azure handles auth internally) ││
                                       │  └─────────────────────────────────┘│
                                       └─────────────────────────────────────┘
```

#### Why No AZURE_CLIENT_SECRET?

Traditional service principal auth requires storing a password (`AZURE_CLIENT_SECRET`) in GitHub secrets. This has security risks:
- Secrets can be leaked
- Secrets expire and need rotation
- Secrets are stored in multiple places

**OIDC eliminates this entirely:**

1. GitHub Actions requests an OIDC token from GitHub's token service
2. The token contains claims like `repo:xshopai/product-service:environment:dev`
3. GitHub Actions presents this token to Azure AD
4. Azure AD checks: "Do I have a Federated Credential that matches this claim?"
5. If yes, Azure issues an access token - **no password ever exchanged**

This is why we only store **3 identifiers** (not passwords) as GitHub secrets:

| Secret | What It Is | Why Stored as Secret |
|--------|-----------|---------------------|
| `AZURE_CLIENT_ID` | The Azure AD App's ID | Not sensitive, but centralized management |
| `AZURE_TENANT_ID` | Your Azure AD tenant ID | Not sensitive, but centralized management |
| `AZURE_SUBSCRIPTION_ID` | Which Azure subscription to deploy to | Not sensitive, but centralized management |

These are just **"addresses"** that tell GitHub Actions WHERE to authenticate - not passwords to authenticate WITH.

#### Option A: Use the Setup Script (Recommended)

```bash
cd infrastructure

# Optional: Edit the script to change Azure region (default: swedencentral)
# Open scripts/azure/setup-azure-oidc.sh and modify the LOCATION variable at the top

# Run the setup script (works on Linux, macOS, Windows Git Bash, WSL)
chmod +x scripts/azure/setup-azure-oidc.sh
./scripts/azure/setup-azure-oidc.sh
```

**Configurable Variables** (at top of script):
| Variable | Default | Description |
|----------|---------|-------------|
| `LOCATION` | `swedencentral` | Azure region for deployments |
| `GITHUB_ORG` | `xshopai` | GitHub organization name |
| `APP_DISPLAY_NAME` | `xshopai-github-actions` | Azure AD App display name |
| `ENVIRONMENTS` | `dev staging prod` | Deployment environments |

The script will:
1. Create Azure AD Application (`xshopai-github-actions`)
2. Create Service Principal
3. Assign necessary roles (Contributor, User Access Administrator, AcrPush)
4. Create federated credentials for all repositories
5. Display the GitHub secrets to configure

#### Option B: Manual Setup

If you prefer manual setup or need to troubleshoot:

```bash
# Variables
GITHUB_ORG="xshopai"
APP_NAME="xshopai-github-actions"

# 1. Create Azure AD Application
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
APP_OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)

echo "App ID (Client ID): $APP_ID"
echo "App Object ID: $APP_OBJECT_ID"

# 2. Create Service Principal
az ad sp create --id $APP_ID
SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# 3. Assign Roles
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create \
    --assignee $SP_OBJECT_ID \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
    --assignee $SP_OBJECT_ID \
    --role "User Access Administrator" \
    --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
    --assignee $SP_OBJECT_ID \
    --role "AcrPush" \
    --scope "/subscriptions/$SUBSCRIPTION_ID"

# 4. Create Federated Credentials (repeat for each repo)
# Infrastructure repo - main branch
az ad app federated-credential create --id $APP_OBJECT_ID --parameters '{
    "name": "infrastructure-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
}'

# Infrastructure repo - dev environment
az ad app federated-credential create --id $APP_OBJECT_ID --parameters '{
    "name": "infrastructure-env-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/infrastructure:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
}'

# Repeat for each service repo and environment...
# See full list in the setup script
```

#### Federated Credentials Required

Federated credentials create a **trust relationship** between GitHub and Azure. Each credential defines: "When GitHub sends a token with THIS specific claim, trust it."

**The setup script creates 68 federated credentials:**
- 17 repositories × 4 credential patterns per repo = 68 total

Each repository needs credentials for:
- `ref:refs/heads/main` - For builds triggered on main branch push
- `environment:dev` - For deployments to dev environment
- `environment:staging` - For deployments to staging environment  
- `environment:prod` - For deployments to production environment

**Why 4 patterns per repo?**

GitHub Actions generates different OIDC token claims based on trigger:
- Push to main → token contains `ref:refs/heads/main`
- Deployment to dev environment → token contains `environment:dev`

Azure checks: "Does ANY federated credential match this token's claims?" If yes, authentication succeeds.

**Repositories requiring credentials:**
- infrastructure
- admin-service
- admin-ui
- audit-service
- auth-service
- cart-service
- chat-service
- customer-ui
- inventory-service
- notification-service
- order-processor-service
- order-service
- payment-service
- product-service
- review-service
- user-service
- web-bff

---

### Step 3: GitHub Configuration

#### 3.1 Understanding GitHub Workflow OIDC Configuration

All GitHub workflows are already configured for OIDC authentication. Here's what makes it work:

**Required Workflow Configuration:**

```yaml
# 1. Permission to request OIDC tokens
permissions:
  id-token: write    # Required for OIDC
  contents: read     # To checkout code

# 2. Azure login using OIDC (no client-secret!)
- name: Azure Login
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    # Note: NO client-secret parameter - this is OIDC!
```

**Key Points:**
- `permissions: id-token: write` - This allows the workflow to request an OIDC token from GitHub
- `azure/login@v2` - The v2 action supports OIDC natively
- No `client-secret` parameter - If you see this, it's using OIDC; if you see `client-secret`, it's using service principal auth

**Service Workflows Use Reusable Workflow:**

Most service repos don't directly contain Azure login code. Instead, they call a reusable workflow:

```yaml
# In service repo (e.g., product-service/.github/workflows/deploy.yml)
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: product-service
      environment: dev
    secrets: inherit  # Passes org secrets (AZURE_CLIENT_ID, etc.) to reusable workflow
```

The `secrets: inherit` keyword passes all organization secrets to the reusable workflow, which then handles the Azure login.

#### 3.2 Organization Secrets

##### Option A: Use the Setup Script (Recommended)

```bash
cd infrastructure

# Ensure you're logged into GitHub CLI
gh auth login

# Run the secrets setup script
chmod +x scripts/azure/setup-github-secrets.sh
./scripts/azure/setup-github-secrets.sh
```

The script will automatically:
1. Retrieve Azure credentials from your current Azure CLI session
2. Look up the Azure AD App created by `setup-azure-oidc.sh`
3. Set all three organization secrets
4. Verify the secrets were created

##### Option B: Manual Setup

Go to: `https://github.com/organizations/xshopai/settings/secrets/actions`

Add these secrets at the **organization level** (so all repos can use them):

| Secret Name | Value | How to Get |
|-------------|-------|------------|
| `AZURE_CLIENT_ID` | Azure AD App ID | From setup script output or `az ad app show --display-name "xshopai-github-actions" --query appId -o tsv` |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `az account show --query id -o tsv` |

#### 3.3 Create GitHub Environments

For each repository that deploys to Azure, create these environments:

1. Go to repository → Settings → Environments
2. Create environments: `dev`, `staging`, `prod`
3. For `staging` and `prod`, consider adding:
   - Required reviewers
   - Wait timer
   - Branch protection rules

**Quick way to create environments (via GitHub CLI):**

```bash
# Install GitHub CLI if not already installed
# winget install GitHub.cli

# Login to GitHub
gh auth login

# For each repo, create environments
for repo in customer-ui user-service auth-service; do
    gh api repos/xshopai/$repo/environments/dev -X PUT
    gh api repos/xshopai/$repo/environments/staging -X PUT
    gh api repos/xshopai/$repo/environments/prod -X PUT
done
```

---

### Step 4: Infrastructure Deployment

The infrastructure is deployed in layers to handle dependencies properly.

#### Layer Overview

| Layer | Contents | Dependencies |
|-------|----------|--------------|
| Layer 0 | Resource Group, Managed Identity, Log Analytics | None |
| Layer 1 | Container Apps Environment, ACR, Key Vault | Layer 0 |
| Layer 2 | Databases (Cosmos DB, PostgreSQL, Redis) | Layer 1 |
| Layer 3 | Service Bus, Dapr Components | Layer 1, Layer 2 |
| Layer 4 | Container Apps (service shells) | Layer 0, Layer 1 |

#### Deploy via GitHub Actions (Recommended)

1. Go to: `https://github.com/xshopai/infrastructure/actions`
2. Click: **"Deploy Azure Container Apps (Layered)"**
3. Click: **"Run workflow"**
4. Configure:
   - **Environment**: `dev` (start with dev)
   - **Layers to deploy**: `all` (or specific layer number)
   - **Azure Region**: `swedencentral` (or your preferred region)
5. Click: **"Run workflow"**

Monitor the deployment in the Actions tab. Each layer runs sequentially.

#### Deploy via Azure CLI (Alternative)

```bash
cd infrastructure/azure/container-apps/bicep

# Set variables
ENVIRONMENT="dev"
LOCATION="swedencentral"
RESOURCE_GROUP="rg-xshopai-${ENVIRONMENT}"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy all layers
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters environment=$ENVIRONMENT location=$LOCATION

# Or deploy layer by layer
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file layers/layer0-foundation.bicep \
    --parameters environment=$ENVIRONMENT location=$LOCATION
```

---

### Step 5: Post-Deployment Configuration

After infrastructure deployment, run the post-deployment script to configure settings that can't be done via Bicep:

```bash
cd infrastructure

# Optional: Edit the script to change Azure region if different from default
# Open scripts/azure/post-deploy-config.sh and modify the LOCATION variable at the top
# The LOCATION must match the region used during infrastructure deployment

# Run post-deployment configuration
./scripts/azure/post-deploy-config.sh dev
```

**Configurable Variables** (at top of script):
| Variable | Default | Description |
|----------|---------|-------------|
| `LOCATION` | `swedencentral` | Azure region (must match infrastructure deployment) |
| `PROJECT_NAME` | `xshopai` | Project name prefix for resources |

This script will:
1. ✅ Enable ACR Admin User (required for GitHub Actions to push images)
2. ✅ Verify Container Apps Environment is healthy
3. ✅ Display ACR credentials
4. ✅ List deployed Container Apps

#### Manual Steps (if script fails)

```bash
# Get your ACR name (replace xxx with your unique suffix)
az acr list --resource-group rg-xshopai-dev --query "[0].name" -o tsv

# Enable ACR admin user
az acr update --name <acr-name> --admin-enabled true

# Verify
az acr show --name <acr-name> --query "adminUserEnabled"
```

---

### Step 6: Service Deployment

Each service has its own GitHub Actions workflow for deployment.

#### Deploy Customer UI (Example)

1. Go to: `https://github.com/xshopai/customer-ui/actions`
2. Click: **"Deploy to Azure Container Apps"** (or similar)
3. Click: **"Run workflow"**
4. Select environment: `dev`
5. Click: **"Run workflow"**

The workflow will:
1. Run tests
2. Build Docker image
3. Push to Azure Container Registry
4. Update Container App with new image

#### Verify Deployment

```bash
# Get the FQDN of deployed app
az containerapp show \
    --name customer-ui \
    --resource-group rg-xshopai-dev \
    --query "properties.configuration.ingress.fqdn" -o tsv

# Open in browser
# https://<fqdn>
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Azure Container Apps Environment                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                              Dapr Sidecar Injection                      ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       ││
│  │  │ user-service│ │ auth-service│ │cart-service │ │order-service│ ...   ││
│  │  │  + Dapr     │ │  + Dapr     │ │  + Dapr     │ │  + Dapr     │       ││
│  │  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘ └──────┬──────┘       ││
│  └─────────┼───────────────┼───────────────┼───────────────┼───────────────┘│
│            │               │               │               │                 │
│            ▼               ▼               ▼               ▼                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                        Dapr Components (Bicep Resources)                 ││
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐        ││
│  │  │  pubsub    │  │ statestore │  │secret-store│  │configstore │        ││
│  │  │ (SvcBus)   │  │  (Redis)   │  │ (KeyVault) │  │  (Redis)   │        ││
│  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘        ││
│  └────────┼───────────────┼───────────────┼───────────────┼────────────────┘│
└───────────┼───────────────┼───────────────┼───────────────┼─────────────────┘
            │               │               │               │
            ▼               ▼               ▼               ▼
┌───────────────────┐ ┌───────────┐ ┌───────────────┐ ┌───────────┐
│ Azure Service Bus │ │   Redis   │ │  Key Vault    │ │  Redis    │
│   (Topics)        │ │  Cache    │ │  (Secrets)    │ │  (Config) │
└───────────────────┘ └───────────┘ └───────────────┘ └───────────┘
                            │
                            ▼
            ┌───────────────────────────────┐
            │        Databases              │
            │  ┌─────────────────────────┐  │
            │  │ Cosmos DB (MongoDB API) │  │
            │  │ - users, products,      │  │
            │  │   reviews, carts, ...   │  │
            │  └─────────────────────────┘  │
            │  ┌─────────────────────────┐  │
            │  │    PostgreSQL           │  │
            │  │ - orders, payments,     │  │
            │  │   inventory, audit      │  │
            │  └─────────────────────────┘  │
            └───────────────────────────────┘
```

---

## Resource Naming Convention

All resources follow this pattern: `{type}-xshopai-{environment}[-suffix]`

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| Resource Group | rg-xshopai-dev | rg-xshopai-staging | rg-xshopai-prod |
| Container Apps Env | cae-xshopai-dev | cae-xshopai-staging | cae-xshopai-prod |
| Container Registry | crxshopaidevXXX | crxshopaistagingXXX | crxshopaiprodXXX |
| Key Vault | kv-xshopai-dev | kv-xshopai-staging | kv-xshopai-prod |
| Service Bus | sb-xshopai-dev | sb-xshopai-staging | sb-xshopai-prod |
| Cosmos DB | cosmos-xshopai-dev | cosmos-xshopai-staging | cosmos-xshopai-prod |
| PostgreSQL | psql-xshopai-dev | psql-xshopai-staging | psql-xshopai-prod |
| Redis | redis-xshopai-dev | redis-xshopai-staging | redis-xshopai-prod |
| Managed Identity | id-xshopai-dev | id-xshopai-staging | id-xshopai-prod |
| Log Analytics | log-xshopai-dev | log-xshopai-staging | log-xshopai-prod |

> **Note**: XXX = unique suffix generated during deployment (e.g., `crxshopaidev7x2`)

---

## Environment Configuration

### Service Environment Variables

After deployment, services access configuration via:

1. **Dapr Secret Store** - Secrets from Key Vault
2. **Environment Variables** - Non-sensitive config set during deployment
3. **Dapr Config Store** - Runtime configuration

Example service configuration in Container App:

```yaml
env:
  - name: DAPR_HTTP_PORT
    value: "3500"
  - name: DAPR_GRPC_PORT  
    value: "50001"
  - name: ENVIRONMENT
    value: "dev"
  - name: LOG_LEVEL
    value: "debug"
```

### Accessing Secrets via Dapr

```javascript
// Node.js example
const { DaprClient } = require('@dapr/dapr');
const client = new DaprClient();

// Get secret from Key Vault
const secret = await client.secret.get('secret-store', 'MONGODB_CONNECTION_STRING');
```

```python
# Python example
from dapr.clients import DaprClient

with DaprClient() as client:
    secret = client.get_secret('secret-store', 'MONGODB_CONNECTION_STRING')
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. OIDC Login Fails in GitHub Actions

**Error**: `AADSTS700016: Application with identifier 'xxx' was not found`

**Cause**: Federated credential not configured for the repo/branch/environment combination.

**Solution**:
```bash
# List existing federated credentials
az ad app federated-credential list --id <app-object-id>

# Create missing credential
az ad app federated-credential create --id <app-object-id> --parameters '{
    "name": "customer-ui-env-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:xshopai/customer-ui:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
}'
```

**Important**: The subject must EXACTLY match. Common patterns:
- Branch: `repo:xshopai/REPO:ref:refs/heads/main`
- Environment: `repo:xshopai/REPO:environment:dev`

---

#### 2. ACR Push Fails with "unauthorized"

**Error**: `unauthorized: authentication required` or `Error response from daemon: Get "https://crxshopaidev.azurecr.io/v2/": unauthorized`

**Cause**: ACR Admin user not enabled.

**Solution**:
```bash
# Get ACR name
ACR_NAME=$(az acr list --resource-group rg-xshopai-dev --query "[0].name" -o tsv)

# Enable admin user
az acr update --name $ACR_NAME --admin-enabled true

# Verify
az acr show --name $ACR_NAME --query "adminUserEnabled" -o tsv
# Should output: true
```

---

#### 3. Container App Won't Start

**Symptoms**: App shows "Failed" status, continuous restarts

**Diagnosis**:
```bash
# Check system logs (Dapr sidecar, platform)
az containerapp logs show \
    --name customer-ui \
    --resource-group rg-xshopai-dev \
    --type system

# Check console logs (application)
az containerapp logs show \
    --name customer-ui \
    --resource-group rg-xshopai-dev \
    --type console

# Check revision status
az containerapp revision list \
    --name customer-ui \
    --resource-group rg-xshopai-dev \
    --query "[].{name:name, active:properties.active, healthState:properties.healthState}" \
    -o table
```

**Common Causes**:
- **Missing environment variables**: Check Bicep/workflow for required env vars
- **Health probe failing**: Check health endpoint path
- **Database not accessible**: Verify network/firewall rules
- **Image doesn't exist**: Verify ACR has the image

---

#### 4. Dapr Component Connection Issues

**Error**: `Error connecting to Dapr sidecar` or pub/sub not working

**Diagnosis**:
```bash
# List Dapr components
az containerapp env dapr-component list \
    --name cae-xshopai-dev \
    --resource-group rg-xshopai-dev \
    -o table

# Show specific component
az containerapp env dapr-component show \
    --name pubsub \
    --dapr-env-name cae-xshopai-dev \
    --resource-group rg-xshopai-dev
```

**Common Causes**:
- Service Bus connection string incorrect
- Managed Identity missing role assignments
- Component scopes not including the app

---

#### 5. Deployment Quota Exceeded

**Error**: `QuotaExceeded` during deployment

**Solution**:
```bash
# Check quotas in your region
az vm list-usage --location swedencentral -o table

# If Container Apps quota is the issue, request increase via Azure Portal
# Navigate to: Subscription → Usage + quotas → Request increase
```

---

#### 6. GitHub Actions: "No tests found"

**Error**: Build fails with `No tests found`

**Cause**: Test framework expects tests but none exist or test config is incorrect.

**Solution**: Add `--passWithNoTests` flag in workflow:
```yaml
- name: Run tests
  run: npm test -- --passWithNoTests
```

---

### Useful Diagnostic Commands

```bash
# === Resource Overview ===
# List all resources in resource group
az resource list --resource-group rg-xshopai-dev -o table

# === Container Apps ===
# List all container apps
az containerapp list --resource-group rg-xshopai-dev -o table

# Get app FQDN
az containerapp show --name customer-ui --resource-group rg-xshopai-dev \
    --query "properties.configuration.ingress.fqdn" -o tsv

# Check app health
az containerapp show --name customer-ui --resource-group rg-xshopai-dev \
    --query "properties.runningStatus" -o tsv

# === ACR ===
# List images in ACR
az acr repository list --name <acr-name> -o table

# List tags for an image
az acr repository show-tags --name <acr-name> --repository customer-ui -o table

# === Service Bus ===
# List topics
az servicebus topic list --namespace-name sb-xshopai-dev \
    --resource-group rg-xshopai-dev -o table

# === Cosmos DB ===
# List databases
az cosmosdb mongodb database list --account-name cosmos-xshopai-dev \
    --resource-group rg-xshopai-dev -o table

# === PostgreSQL ===
# Check server status
az postgres flexible-server show --name psql-xshopai-dev \
    --resource-group rg-xshopai-dev --query "state" -o tsv
```

---

## Cost Management

### Estimated Monthly Costs (Dev Environment)

| Resource | SKU | Est. Cost |
|----------|-----|-----------|
| Container Apps | Consumption | ~$0-20 (scales to 0) |
| Container Registry | Basic | ~$5 |
| Cosmos DB | Serverless | ~$0-25 (pay per RU) |
| PostgreSQL | Burstable B1ms | ~$15 |
| Redis | Basic C0 | ~$15 |
| Service Bus | Basic | ~$0.05/million ops |
| Key Vault | Standard | ~$0.03/10k ops |
| Log Analytics | Pay-as-you-go | ~$2-5 |
| **Total** | | **~$40-90/month** |

### Cost Optimization Tips

**Development Environment:**
- ✅ Use consumption plan (scale to 0 when idle)
- ✅ Use smaller database SKUs (Burstable for PostgreSQL)
- ✅ Use serverless Cosmos DB
- ✅ Set short log retention (7-14 days)
- ✅ Delete unused revisions

**Production Environment:**
- Consider dedicated plan for predictable costs
- Enable autoscaling with appropriate min/max
- Use reserved capacity for databases (1-3 year)
- Enable geo-redundancy only if needed

### Cleaning Up Resources

```bash
# Delete entire resource group (WARNING: destroys everything)
az group delete --name rg-xshopai-dev --yes --no-wait

# Delete specific container app
az containerapp delete --name customer-ui --resource-group rg-xshopai-dev

# Stop databases (PostgreSQL)
az postgres flexible-server stop --name psql-xshopai-dev --resource-group rg-xshopai-dev
```

---

## Security Best Practices

1. **Managed Identity** - All services use user-assigned managed identity (no credentials in code)
2. **Key Vault** - All secrets stored in Key Vault, accessed via Dapr secret store
3. **Network Isolation** - Internal services don't expose external endpoints
4. **RBAC** - Least privilege access to all resources
5. **TLS** - All traffic encrypted (handled by Container Apps)
6. **OIDC** - GitHub Actions uses OIDC instead of service principal secrets

---

## Next Steps

After infrastructure deployment:

1. ✅ Deploy individual services using their GitHub Actions workflows
2. 🔜 Configure custom domains and SSL certificates
3. 🔜 Set up monitoring alerts in Azure Monitor
4. 🔜 Configure backup policies for databases
5. 🔜 Set up staging and production environments

---

## Support

For issues:
1. Check the [Troubleshooting](#troubleshooting) section above
2. Review GitHub Actions logs
3. Check Azure Portal for resource health
4. Open an issue in the infrastructure repository
