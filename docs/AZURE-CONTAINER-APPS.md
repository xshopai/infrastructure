# Azure Container Apps Setup Guide

This guide explains how to deploy the xshopai platform infrastructure to Azure Container Apps.

## Prerequisites

- Azure CLI 2.50+ with Bicep CLI
- Azure subscription with Contributor access
- GitHub repository with Actions enabled

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
│  │  │  pubsub    │  │ statestore │  │secretstore │  │configstore │        ││
│  │  │ (SvcBus)   │  │  (Redis)   │  │ (KeyVault) │  │  (Redis)   │        ││
│  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘        ││
│  └────────┼───────────────┼───────────────┼───────────────┼────────────────┘│
└───────────┼───────────────┼───────────────┼───────────────┼─────────────────┘
            │               │               │               │
            ▼               ▼               ▼               ▼
┌───────────────────┐ ┌───────────┐ ┌───────────────┐ ┌───────────┐
│ Azure Service Bus │ │   Redis   │ │  Key Vault    │ │  Redis    │
│   (9 Topics)      │ │  Cache    │ │  (Secrets)    │ │  (Config) │
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

## Deployment Steps

### 1. Azure Login

```bash
az login
az account set --subscription <subscription-id>
```

### 2. Create Resource Group

```bash
# Development
az group create --name rg-xshopai-dev --location uksouth

# Staging
az group create --name rg-xshopai-staging --location uksouth

# Production
az group create --name rg-xshopai-prod --location uksouth
```

### 3. Deploy Infrastructure

#### Option A: Azure CLI

```bash
# Deploy dev environment
az deployment group create \
  --resource-group rg-xshopai-dev \
  --template-file azure/container-apps/bicep/main.bicep \
  --parameters azure/container-apps/bicep/parameters/dev.bicepparam \
  --parameters postgresAdminLogin=xshopaiadmin \
  --parameters postgresAdminPassword='<your-secure-password>'
```

#### Option B: GitHub Actions (Recommended)

1. Configure repository secrets (see below)
2. Go to Actions → "Deploy Azure Container Apps Infrastructure"
3. Select environment and run workflow

### 4. Verify Deployment

```bash
# List all resources in resource group
az resource list --resource-group rg-xshopai-dev -o table

# Get Container Apps Environment details
az containerapp env show \
  --name cae-xshopai-dev \
  --resource-group rg-xshopai-dev

# List Dapr components
az containerapp env dapr-component list \
  --name cae-xshopai-dev \
  --resource-group rg-xshopai-dev \
  -o table
```

## GitHub Actions Setup

### Required Secrets

| Secret | Description | How to Get |
|--------|-------------|------------|
| `AZURE_CLIENT_ID` | SP Application ID | `az ad sp show --id <app-id> --query appId -o tsv` |
| `AZURE_TENANT_ID` | Azure AD Tenant | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Subscription | `az account show --query id -o tsv` |
| `POSTGRES_ADMIN_LOGIN` | DB admin username | Choose a username |
| `POSTGRES_ADMIN_PASSWORD` | DB admin password | Generate secure password |

### OIDC Setup for GitHub Actions

```bash
# 1. Create Azure AD Application
APP_ID=$(az ad app create --display-name "xshopai-github-actions" --query appId -o tsv)

# 2. Create Service Principal
az ad sp create --id $APP_ID

# 3. Get Object ID
OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# 4. Create Federated Credential for main branch
az ad app federated-credential create --id $APP_ID --parameters @- << EOF
{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:xshopai/infrastructure:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

# 5. Create Federated Credential for environment deployments
for env in dev staging prod; do
  az ad app federated-credential create --id $APP_ID --parameters @- << EOF
{
  "name": "github-env-$env",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:xshopai/infrastructure:environment:$env",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
done

# 6. Assign Contributor role to subscription
az role assignment create \
  --assignee $OBJECT_ID \
  --role "Contributor" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"

# 7. Assign User Access Administrator for managed identity operations
az role assignment create \
  --assignee $OBJECT_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

## Resource Naming Convention

All resources follow this pattern: `{type}-xshopai-{environment}`

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| Resource Group | rg-xshopai-dev | rg-xshopai-staging | rg-xshopai-prod |
| Container Apps Env | cae-xshopai-dev | cae-xshopai-staging | cae-xshopai-prod |
| Container Registry | crxshopaidev | crxshopaistaging | crxshopaiprod |
| Key Vault | kv-xshopai-dev | kv-xshopai-staging | kv-xshopai-prod |
| Service Bus | sb-xshopai-dev | sb-xshopai-staging | sb-xshopai-prod |

## Environment Variables

After deployment, services access configuration via:

1. **Dapr Secret Store** - Secrets from Key Vault
2. **Environment Variables** - Non-sensitive config
3. **Dapr Config Store** - Runtime configuration

Example service configuration:

```yaml
env:
  - name: DAPR_HTTP_PORT
    value: "3500"
  - name: DAPR_GRPC_PORT  
    value: "50001"
  - name: DATABASE_NAME
    value: "users"
```

Secrets accessed via Dapr:

```javascript
// Node.js example
const secret = await daprClient.secret.get('secretstore', 'MONGODB_CONNECTION_STRING');
```

## Troubleshooting

### Deployment Fails with "QuotaExceeded"

```bash
# Check your subscription quotas
az vm list-usage --location uksouth -o table

# Request quota increase via Azure Portal
```

### Container App Won't Start

```bash
# Check logs
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-dev \
  --type console

# Check Dapr sidecar logs
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-dev \
  --type system
```

### Dapr Component Connection Issues

```bash
# Verify component configuration
az containerapp env dapr-component show \
  --name pubsub \
  --dapr-env-name cae-xshopai-dev \
  --resource-group rg-xshopai-dev

# Check Service Bus connection
az servicebus namespace show \
  --name sb-xshopai-dev \
  --resource-group rg-xshopai-dev
```

## Cost Optimization

### Development Environment

- Use consumption plan (pay per use)
- Scale to 0 when idle
- Use smaller database SKUs

### Production Environment

- Consider dedicated plan for predictable costs
- Enable autoscaling with appropriate limits
- Use reserved capacity for databases

## Security Considerations

1. **Managed Identity** - All services use user-assigned managed identity
2. **Key Vault** - All secrets stored in Key Vault, accessed via Dapr
3. **Network Isolation** - Internal services don't expose external endpoints
4. **RBAC** - Least privilege access to all resources
5. **TLS** - All traffic encrypted (handled by Container Apps)

## Next Steps

After infrastructure deployment:

1. Deploy individual services using their CI/CD pipelines
2. Configure custom domains and SSL certificates
3. Set up monitoring alerts in Azure Monitor
4. Configure backup policies for databases
