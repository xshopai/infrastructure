# Azure Setup Scripts for xshopai

Collection of automation scripts for one-time Azure and GitHub configuration.

## 🎯 Quick Start (New Organization Setup)

Run these scripts in order when setting up xshopai for the first time:

```bash
cd infrastructure/scripts/azure

# Step 1: Authenticate with Azure and GitHub
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
gh auth login

# Step 2: Setup Azure OIDC authentication
./setup-azure-oidc.sh

# Step 3: Create GitHub environments (REQUIRED!)
./setup-github-environments.sh

# Step 4: Configure GitHub organization secrets
./setup-github-secrets.sh

# Step 5: Post-deployment configuration (run AFTER infrastructure deployed)
./post-deploy-config.sh
```

**Total setup time**: ~5-10 minutes

---

## 📋 Script Inventory

### 1. `setup-azure-oidc.sh`

**Purpose**: Configure Azure OIDC authentication for GitHub Actions (no secrets!)

**What it does**:
- Creates Azure AD App Registration: `xshopai-github-actions`
- Assigns service principal roles: Contributor, User Access Administrator, AcrPush
- Configures GitHub OIDC subject customization (environment-only)
- Creates 2 federated credentials:
  - `xshopai-dev` → subject: `environment:dev`
  - `xshopai-prod` → subject: `environment:prod`

**Output**:
```
AZURE_CLIENT_ID=abc-123...
AZURE_TENANT_ID=def-456...
AZURE_SUBSCRIPTION_ID=ghi-789...
```

**When to run**: Once per Azure subscription (one-time setup)

**Documentation**: See comments in script for OIDC architecture explanation

---

### 2. `setup-github-environments.sh`

**Purpose**: Create GitHub environments in all repositories

**⚠️ CRITICAL**: This script is **REQUIRED** for OIDC authentication to work!

**What it does**:
- Creates `dev` environment in 17 repositories (infrastructure + 16 services)
- Creates `prod` environment in 17 repositories
- Configures production protection rules (optional: add manual approval)

**Why required?**:
- Azure federated credentials match on subject claim: `environment:dev|prod`
- Without GitHub environments, workflows can't authenticate to Azure
- GitHub Actions `environment:` key requires the environment to exist

**Repositories affected**:
```
infrastructure        admin-service       admin-ui
audit-service         auth-service        cart-service
chat-service          customer-ui         inventory-service
notification-service  order-processor-service  order-service
payment-service       product-service     review-service
user-service          web-bff
```

**Output**:
```
✅ Environment Setup Complete!

📊 Summary:
   Repositories processed: 17
   Environments created: 34 (dev + prod per repo)
```

**When to run**: Once after `setup-azure-oidc.sh` (one-time setup)

**Verify**:
```bash
gh api repos/xshopai/product-service/environments
```

---

### 3. `setup-github-secrets.sh`

**Purpose**: Configure GitHub organization secrets for Azure authentication

**What it does**:
- Creates organization-level secrets (shared across all repos):
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- Verifies secrets were created correctly

**Input**: Copy values from `setup-azure-oidc.sh` output

**When to run**: Once after `setup-azure-oidc.sh` (one-time setup)

**Verify**:
```bash
gh secret list --org xshopai
```

---

### 4. `post-deploy-config.sh`

**Purpose**: Post-deployment configuration (Dapr, App Insights, etc.)

**What it does**:
- TBD: Configure Dapr components
- TBD: Setup Application Insights instrumentation keys
- TBD: Configure service connection strings

**When to run**: After deploying infrastructure (Phase 1-3 complete)

---

### 5. `gh-auth.sh`

**Purpose**: Helper script for GitHub CLI authentication

**What it does**:
- Checks if GitHub CLI is authenticated
- Provides instructions if not authenticated

**When to run**: Anytime before using other scripts

---

## 🔄 Common Workflows

### New Developer Onboarding

When a new developer clones the organization repositories:

```bash
# Clone the organization
gh repo clone xshopai/infrastructure

# The environments already exist (created by setup-github-environments.sh)
# They just need to authenticate with Azure and GitHub:
az login
gh auth login

# Ready to deploy!
```

**Note**: GitHub environments are created at the organization level, so new developers don't need to run setup scripts.

---

### Re-running Setup Scripts (Idempotent)

All scripts are designed to be idempotent (safe to re-run):

```bash
# Re-run OIDC setup (will skip if already configured)
./setup-azure-oidc.sh

# Re-run environment setup (will skip existing environments)
./setup-github-environments.sh

# Re-run secrets setup (will update existing secrets)
./setup-github-secrets.sh
```

---

### Adding a New Service Repository

When adding a new microservice:

1. Create the repository in GitHub organization
2. Add repo to `SERVICE_REPOS` array in `setup-github-environments.sh`
3. Re-run environment setup:
   ```bash
   ./setup-github-environments.sh
   ```

The script will skip existing repos and only create environments in the new repo.

---

### Rotating Azure Credentials

OIDC tokens are automatically rotated by Azure (no manual rotation needed).

To recreate federated credentials:

```bash
# Delete existing federated credentials
az ad app federated-credential delete --id $APP_ID --federated-credential-id xshopai-dev
az ad app federated-credential delete --id $APP_ID --federated-credential-id xshopai-prod

# Re-run OIDC setup
./setup-azure-oidc.sh
```

---

## 🛠️ Troubleshooting

### "GitHub CLI not authenticated"

```bash
gh auth login
# Follow prompts to authenticate
```

### "Azure CLI not authenticated"

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### "Federated credential already exists"

This is safe to ignore. The script will skip existing credentials.

### "Environment already exists"

This is safe to ignore. The script will skip existing environments.

### "Permission denied: setup-github-environments.sh"

```bash
chmod +x setup-github-environments.sh
./setup-github-environments.sh
```

### "API rate limit exceeded"

Wait a few minutes for GitHub API rate limit to reset, then re-run the script.

---

## 📖 Additional Documentation

- **Complete Deployment Guide**: [../../azure/container-apps/bicep/README.md](../../azure/container-apps/bicep/README.md)
- **OIDC Architecture**: See comments in `setup-azure-oidc.sh`
- **GitHub OIDC Docs**: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- **Azure Federated Credentials**: https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation

---

## 🔐 Security Notes

### What Gets Stored in GitHub?

**Organization Secrets** (safe to store):
- `AZURE_CLIENT_ID` - Azure AD Application (Client) ID
- `AZURE_TENANT_ID` - Azure AD Tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure Subscription ID

**NOT Stored** (OIDC eliminates the need):
- ❌ `AZURE_CLIENT_SECRET` - No secrets stored!
- ❌ Service principal passwords
- ❌ Certificates

### Benefits of OIDC

✅ No secrets stored in GitHub  
✅ Auto-rotated tokens (short-lived)  
✅ Scoped per environment (dev/prod isolation)  
✅ Auditable in Azure AD sign-in logs  
✅ Follows Microsoft's security best practices  

### Federated Credential Subject Pattern

We use **environment-only** subject pattern:
```json
{
  "subject": "environment:dev"
}
```

**Benefits**:
- Only 2 federated credentials total (vs 50+ for repo-specific)
- No dependency on repository names
- No dependency on workflow filenames
- Easier to manage at scale

**Security**:
- `dev` credential cannot access `prod` resources (environment isolation)
- OIDC tokens are short-lived (15 minutes)
- Azure RBAC controls what the service principal can access

---

## 🤝 Contributing

When adding new setup automation:

1. Make scripts idempotent (safe to re-run)
2. Add clear documentation headers
3. Provide usage examples
4. Update this README with script details
5. Test on a fresh Azure subscription
6. Add verification steps (how to check if it worked)

---

## 📝 License

See [LICENSE](../../../LICENSE) for details.
