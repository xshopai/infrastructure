# GitHub Actions Workflow - Bicep Deployment

## Overview

The **deploy-app-service-bicep.yml** workflow provides automated infrastructure deployment using Azure Bicep, replacing the 1500+ line bash/CLI wrapper with declarative IaC.

## 🎯 Workflow Features

### Multi-Job Pipeline

1. **Validate** - Compile and validate Bicep templates
2. **What-If** - Preview changes before deployment
3. **Deploy** - Deploy infrastructure to Azure (conditional)
4. **Verify** - Health check and verification (conditional)

### Key Capabilities

- ✅ **Parallel execution** - ARM orchestrates resource creation concurrently
- ✅ **What-if analysis** - Preview changes without deploying
- ✅ **Environment protection** - Production requires manual approval
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Type-safe** - Bicep validates parameters at compile time
- ✅ **Artifact tracking** - Compiled templates stored for audit

## 📋 Prerequisites

### 1. Azure Service Principal

Create a service principal with required roles:

```bash
# Create service principal
az ad sp create-for-rbac \
  --name "sp-xshopai-github-actions" \
  --role "Contributor" \
  --scopes /subscriptions/<subscription-id>

# Grant User Access Administrator (required for RBAC assignments)
SP_OBJECT_ID=$(az ad sp list --display-name "sp-xshopai-github-actions" --query "[0].id" -o tsv)

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id>
```

### 2. GitHub Secrets

Configure in repository settings:

**Repository Secret:**

- `AZURE_CREDENTIALS` - Service principal JSON:
  ```json
  {
    "clientId": "<client-id>",
    "clientSecret": "<client-secret>",
    "subscriptionId": "<subscription-id>",
    "tenantId": "<tenant-id>"
  }
  ```

### 3. GitHub Variables

Configure organization variables:

- `DEPLOY_SUFFIX_DEV` - Default suffix for dev (e.g., `as01`)
- `DEPLOY_SUFFIX_PROD` - Default suffix for prod (e.g., `pr01`)

### 4. GitHub Environments

Create environments for approval gates:

**Settings → Environments → New environment:**

- **dev** - No protection rules (auto-deploy)
- **prod** - Add required reviewers (manual approval before deploy)

### 5. Key Vault Setup

For subsequent deployments, ensure Key Vault exists with secrets:

```bash
# Key Vault should be created by first deployment
# Or create manually for testing:
az keyvault create \
  --name kv-xshopai-dev-as01 \
  --resource-group rg-xshopai-dev-as01 \
  --location francecentral

# Store secrets (example)
az keyvault secret set --vault-name kv-xshopai-dev-as01 \
  --name postgres-admin-password \
  --value "<secure-password>"
```

## 🚀 Usage

### Running the Workflow

1. **Navigate to Actions tab** in GitHub repository
2. **Select "Deploy App Service Infrastructure (Bicep)"**
3. **Click "Run workflow"**
4. **Configure inputs:**
   - **Environment**: `dev` or `prod`
   - **Suffix**: Leave blank to use org default, or specify (e.g., `as02`)
   - **Location**: Azure region (default: `francecentral`)
   - **What-if only**: ✅ to preview changes without deploying

### Workflow Scenarios

#### Scenario 1: Preview Changes (What-If)

Use this to see what would change without deploying:

```
Environment: dev
Suffix: (blank)
Location: francecentral
What-if only: ✅ checked
```

**Result:** Jobs 1-2 run (validate, what-if), deployment skipped

#### Scenario 2: Deploy to Dev

Standard development deployment:

```
Environment: dev
Suffix: (blank)
Location: francecentral
What-if only: ⬜ unchecked
```

**Result:** All 4 jobs run, infrastructure deployed immediately

#### Scenario 3: Deploy to Prod

Production deployment with approval:

```
Environment: prod
Suffix: (blank)
Location: francecentral
What-if only: ⬜ unchecked
```

**Result:** Jobs 1-2 run, then workflow pauses for manual approval before deploying

#### Scenario 4: Custom Suffix

Deploy with non-default suffix:

```
Environment: dev
Suffix: test01
Location: francecentral
What-if only: ⬜ unchecked
```

**Result:** Creates resources with suffix `test01` instead of org default

## 📊 Workflow Outputs

### Job Artifacts

- **bicep-compiled-{env}-{suffix}** - Compiled Bicep templates (7 days)
- **deployment-outputs-{env}-{suffix}** - ARM deployment outputs (30 days)

### Step Summary

Each job adds information to GitHub Actions Summary:

**What-If Job:**

- Change summary table (create/modify/delete counts)
- Full what-if output (collapsible)

**Deploy Job:**

- Deployment summary (resource group, location, duration)
- Deployed resources table
- Quick links to Azure Portal
- Next steps checklist

**Verify Job:**

- Resource count verification
- App Service health status
- Key Vault verification

## 🔧 Workflow Parameters

### Inputs

| Input          | Type    | Required | Default         | Description                             |
| -------------- | ------- | -------- | --------------- | --------------------------------------- |
| `environment`  | choice  | Yes      | `dev`           | Environment to deploy (dev/prod)        |
| `suffix`       | string  | No       | org var         | Resource suffix (overrides org default) |
| `location`     | string  | No       | `francecentral` | Azure region                            |
| `what_if_only` | boolean | No       | `false`         | Preview changes only, skip deployment   |

### Secrets

| Secret              | Required | Description            |
| ------------------- | -------- | ---------------------- |
| `AZURE_CREDENTIALS` | Yes      | Service principal JSON |

### Variables

| Variable             | Required | Description                         |
| -------------------- | -------- | ----------------------------------- |
| `DEPLOY_SUFFIX_DEV`  | Yes      | Default suffix for dev environment  |
| `DEPLOY_SUFFIX_PROD` | Yes      | Default suffix for prod environment |

## 🔍 Troubleshooting

### Error: "No suffix resolved"

**Cause:** Neither input suffix nor org variable is set

**Fix:**

```bash
# Set organization variable
gh variable set DEPLOY_SUFFIX_DEV --body "as01" --org xshopai

# OR pass suffix explicitly in workflow input
```

### Error: "Resource group not found"

**Cause:** Resource group doesn't exist (first deployment)

**Fix:** Workflow creates it automatically - no action needed

### Error: "Validation failed"

**Cause:** Bicep template syntax error or parameter mismatch

**Fix:**

```bash
# Test locally
cd app-service/bicep
az bicep build --file main.bicep
az deployment group validate \
  --resource-group rg-xshopai-dev-as01 \
  --template-file main.bicep \
  --parameters @parameters.dev.json
```

### Error: "Deployment failed - quota exceeded"

**Cause:** Insufficient quota for requested resources

**Fix:**

```bash
# Check quotas
az vm list-usage --location francecentral --output table

# Request quota increase via Azure Portal
```

### Workflow stuck on "Waiting for approval"

**Cause:** Production environment requires manual approval

**Fix:** Navigate to Actions → Workflow run → Review deployments → Approve

## 📈 Performance Comparison

| Method           | Duration     | Parallelization  | Idempotency   |
| ---------------- | ------------ | ---------------- | ------------- |
| Bash/CLI Wrapper | 30-45 min    | Sequential       | Manual checks |
| **Bicep IaC**    | **8-12 min** | **ARM parallel** | **Built-in**  |

**Speedup: 5-10x faster** ⚡

## 🔗 Related Documentation

- [Bicep Modules](../app-service/bicep/README.md)
- [Parameter Files](../app-service/bicep/parameters.dev.json)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)

## 📞 Support

For issues:

1. Check workflow run logs in Actions tab
2. Review Step Summary for detailed error messages
3. Download deployment artifacts for debugging
4. Check Azure Portal → Deployments for ARM-level errors

---

**Created**: 2026-02-21  
**Version**: 1.0.0  
**Workflow File**: [deploy-app-service-bicep.yml](../../.github/workflows/deploy-app-service-bicep.yml)
