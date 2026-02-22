# xShopAI Infrastructure Setup Scripts (OIDC)

One-time setup scripts to prepare GitHub and Azure for xShopAI deployments using OIDC authentication.

## Quick Start

### Step 1: Run Setup Scripts

```bash
cd scripts
./setup-all.sh
```

This automatically:

1. Authenticates GitHub CLI and Azure CLI
2. Creates Azure AD App with federated credentials
3. Sets GitHub organization secrets (OIDC)
4. Sets infrastructure repo secrets (auto-generated)
5. Creates GitHub environments in all repos
6. Configures Key Vault RBAC access (auto-detects your Object ID)

### Step 2: Deploy Infrastructure to Azure

**Required!** Deploy infrastructure to create Key Vault with RBAC role assignments:

```bash
gh workflow run deploy-app-service-bicep.yml -R xshopai/infrastructure \
  -f environment=dev -f suffix=bicep
```

This deployment will:

- Create all Azure resources (App Services, Key Vault, databases, etc.)
- Grant you **Key Vault Secrets Officer** access automatically
- Store all secrets in Azure Key Vault
- Enable you to view and manage secrets in Azure Portal

**Monitor deployment:**

```bash
gh run list --repo xshopai/infrastructure --workflow deploy-app-service-bicep.yml --limit 1
```

## Why OIDC?

**Industry standard** - Microsoft and GitHub recommend OIDC over service principal secrets.

| Service Principal           | OIDC (What we use) |
| --------------------------- | ------------------ |
| Secret stored in GitHub     | No secrets         |
| Must rotate every 1-2 years | Never expires      |
| Secret can leak             | Nothing to leak    |

## Prerequisites

The scripts check and prompt for:

1. **GitHub CLI** - Will run `gh-auth.sh` if not authenticated
2. **Azure CLI** - Will run `az login` if not authenticated
3. **openssl** - Required for generating secrets

**Permissions required:**

- GitHub: Organization admin access
- Azure: Subscription Contributor + Azure AD App Registration

## Scripts

| Script                         | Purpose                                      |
| ------------------------------ | -------------------------------------------- |
| `setup-all.sh`                 | Master script - runs everything              |
| `setup-azure-oidc.sh`          | Creates Azure AD App + federated credentials |
| `setup-github-secrets.sh`      | Sets org + repo secrets                      |
| `setup-github-environments.sh` | Creates dev/prod environments                |
| `gh-auth.sh`                   | GitHub CLI auth helper                       |

## What Gets Created

### Azure AD App

- **Name**: `xshopai-github-actions`
- **Federated credentials**: `xshopai-dev`, `xshopai-prod`
- **Roles**: Contributor, User Access Administrator, AcrPush

### GitHub Organization Secrets (OIDC)

- `AZURE_CLIENT_ID` - Azure AD App client ID
- `AZURE_TENANT_ID` - Azure AD tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID

### GitHub Infrastructure Repo Secrets

- Database passwords (Postgres, MySQL, SQL, RabbitMQ)
- `JWT_SECRET` - For auth tokens
- Service authentication tokens (7 services)
- **`KEYVAULT_ADMIN_OBJECT_ID`** - Auto-detected for Key Vault RBAC access

### GitHub Environments (all repos)

- `dev` - Development environment
- `prod` - Production environment

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ORGANIZATION LEVEL                       │
│  AZURE_CLIENT_ID + TENANT_ID + SUBSCRIPTION_ID              │
│                          │                                  │
│           GitHub OIDC Token Exchange (no secrets!)          │
│                          │                                  │
│                          ▼                                  │
│               All repos can deploy to Azure                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│               INFRASTRUCTURE REPO ONLY                      │
│  DB Passwords, JWT, Service Tokens, KEYVAULT_ADMIN_OBJECT_ID│
│                          │                                  │
│                          ▼                                  │
│  Bicep Workflow ────────────► Azure Key Vault               │
│                               (with RBAC access)            │
└─────────────────────────────────────────────────────────────┘

Key Vault RBAC Flow:
1. setup-github-secrets.sh auto-detects your Azure AD Object ID
2. Sets KEYVAULT_ADMIN_OBJECT_ID GitHub secret
3. Bicep deployment creates Key Vault role assignment
4. You get Key Vault Secrets Officer access automatically
```

## Deployment Workflow

### 1. Setup (One-time)

Run `./setup-all.sh` to configure GitHub and Azure with OIDC authentication.

### 2. Deploy Infrastructure (Required)

Deploy platform infrastructure to create all Azure resources:

```bash
gh workflow run deploy-app-service-bicep.yml -R xshopai/infrastructure \
  -f environment=dev -f suffix=bicep
```

**What this creates:**

- Resource Group
- App Service Plan
- 16 App Services (one per microservice)
- Azure Key Vault (with your RBAC access)
- Container Registry
- Databases (PostgreSQL, MySQL, SQL Server)
- Message Queue (RabbitMQ)
- Dapr configuration

### 3. Deploy Services (Ongoing)

After infrastructure is deployed, deploy individual microservices:

```bash
# Deploy a single service
gh workflow run ci-app-service.yml -R xshopai/user-service \
  -f environment=dev -f suffix=bicep

# Deploy all services
for repo in admin-service auth-service cart-service inventory-service \
            notification-service order-service order-processor-service \
            payment-service product-service review-service user-service \
            web-bff chat-service audit-service admin-ui customer-ui; do
  echo "Deploying $repo..."
  gh workflow run ci-app-service.yml -R xshopai/$repo \
    -f environment=dev -f suffix=bicep
done
```

## Troubleshooting

### "Permission denied" errors

```bash
chmod +x *.sh
```

### OIDC token exchange fails

- Ensure GitHub environment matches federated credential subject
- Check Azure AD App has correct federated credentials
- Verify workflow has `permissions: id-token: write`

### View federated credentials

```bash
az ad app federated-credential list \
  --id $(az ad app list --display-name xshopai-github-actions --query "[0].appId" -o tsv) \
  --output table
```
