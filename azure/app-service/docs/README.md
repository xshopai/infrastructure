# xshopai Infrastructure - App Service Deployment

Infrastructure as Code (IaC) for deploying the xshopai platform to Azure App Service using Bicep templates.

## 📦 What Gets Deployed

### Infrastructure Components

| Resource Type            | Purpose                            | Count     | SKU                    |
| ------------------------ | ---------------------------------- | --------- | ---------------------- |
| **App Service Plan**     | Hosts all containers               | 1         | B1 (dev) / P1v2 (prod) |
| **App Services**         | Microservices + UIs                | 16        | Linux containers       |
| **RabbitMQ (ACI)**       | Message broker                     | 1         | 1 CPU, 2GB RAM         |
| **Cosmos DB**            | MongoDB API (audit-service)        | 1         | Serverless             |
| **PostgreSQL**           | user-service, notification-service | 1         | Standard_B1ms          |
| **MySQL**                | review-service, admin-service      | 1         | Standard_B1s           |
| **SQL Server**           | order/payment/cart-service         | 1 + 3 DBs | Basic tier             |
| **Redis Cache**          | Session/caching                    | 1         | Basic C0               |
| **Key Vault**            | Secrets management                 | 1         | Standard               |
| **Application Insights** | Monitoring/logging                 | 1         | Shared                 |
| **Log Analytics**        | Log aggregation                    | 1         | PerGB2018              |

### App Services Deployed

1. `auth-service` - JWT authentication
2. `user-service` - User profiles
3. `product-service` - Product catalog
4. `inventory-service` - Stock management
5. `cart-service` - Shopping cart
6. `review-service` - Product reviews
7. `payment-service` - Payment processing
8. `order-service` - Order management
9. `order-processor-service` - Order fulfillment
10. `notification-service` - Email/SMS notifications
11. `audit-service` - Audit logging
12. `admin-service` - Admin operations
13. `chat-service` - Customer support
14. `web-bff` - Backend-for-frontend
15. `customer-ui` - Customer React SPA
16. `admin-ui` - Admin React SPA

---

## 🚀 Deployment

### Prerequisites

✅ Azure CLI installed  
✅ GitHub account with admin access to `xshopai/infrastructure` repo  
✅ Azure subscription  
✅ Service Principal created (via `deployment/azure/app-service/scripts/azure-setup.sh`)  
✅ GitHub organization secrets configured  
✅ GitHub environments configured (via `deployment/azure/app-service/scripts/github-setup.sh`)  
✅ Container Registry with service images built

**Note**: Steps 4-6 are automated by `deployment/azure/app-service/scripts/deploy.sh`

### Option 1: Automatic Deployment (CI)

**Trigger**: Push to `main` branch (automatic)

```bash
# Make changes to Bicep templates
cd azure/app-service/bicep
vim main.bicep

# Commit and push
git add .
git commit -m "Update infrastructure"
git push origin main
```

Infrastructure is **automatically deployed to development** environment.

### Option 2: Manual Deployment (CD)

**Trigger**: GitHub Actions workflow dispatch (manual)

1. Go to GitHub: https://github.com/xshopai/infrastructure/actions
2. Select **"Deploy App Service Infrastructure"** workflow
3. Click **"Run workflow"**
4. Select environment:
   - `development` - No approval required
   - `production` - **Requires 2 approvals** (configured in GitHub environment)
5. Click **"Run workflow"**

**Production Deployment**:

- Requires manual trigger (no automatic deployment)
- Requires review from 2 team members
- Environment protection rules enforced by GitHub

---

## 🔐 Secrets Management

### Auto-Generated Secrets (by Workflow)

The GitHub Actions workflow automatically generates these secrets:

| Secret Name          | Purpose                   | Generation Method                |
| -------------------- | ------------------------- | -------------------------------- |
| `jwt-private-key`    | Auth service signs tokens | OpenSSL RSA 2048-bit             |
| `jwt-public-key`     | Services verify tokens    | OpenSSL RSA public key           |
| `admin-password`     | Admin UI login            | OpenSSL rand (32 chars)          |
| `mongodb-password`   | Cosmos DB password        | OpenSSL rand (32 chars)          |
| `postgres-password`  | PostgreSQL password       | OpenSSL rand (32 chars)          |
| `mysql-password`     | MySQL password            | OpenSSL rand (32 chars)          |
| `sqlserver-password` | SQL Server password       | OpenSSL rand (32 chars) + suffix |

### View Secrets in Azure Portal

After deployment:

1. Navigate to Key Vault: `kv-xshopai-gh-dev` (or `kv-xshopai-gh-pro`)
2. Go to **Secrets** section
3. Click any secret to view its value
4. Use for local testing if needed

### External API Keys (Optional - Production Only)

For production, manually add external API keys:

```bash
# Stripe (payment processing)
az keyvault secret set \
  --vault-name kv-xshopai-gh-pro \
  --name stripe-api-key \
  --value "sk_live_..."

# SendGrid (email notifications)
az keyvault secret set \
  --vault-name kv-xshopai-gh-pro \
  --name sendgrid-api-key \
  --value "SG...."

# Twilio (SMS notifications)
az keyvault secret set \
  --vault-name kv-xshopai-gh-pro \
  --name twilio-api-key \
  --value "AC..."
```

---

## 🔧 Configuration

### Environment Variables

App Services are pre-configured with:

- **PORT**: Service-specific port (8000-8014, 3000-3001)
- **NODE_ENV**: `development` or `production`
- **ENVIRONMENT**: `development` or `production`
- **APPLICATIONINSIGHTS_CONNECTION_STRING**: Auto-configured
- **JWT_PRIVATE_KEY / JWT_PUBLIC_KEY**: Key Vault references
- **Database Passwords**: Key Vault references

### Add Custom Environment Variables

```bash
# Example: Add Stripe key to payment-service
az webapp config appsettings set \
  --resource-group rg-xshopai-gh-dev \
  --name app-payment-service-dev \
  --settings "STRIPE_API_KEY=@Microsoft.KeyVault(SecretUri=https://kv-xshopai-gh-dev.vault.azure.net/secrets/stripe-api-key/)"
```

---

## 📊 Monitoring

### Application Insights

**Access**: [Azure Portal](https://portal.azure.com) → Application Insights → `appi-xshopai-gh-{env}`

**Features**:

- Live Metrics (real-time)
- Application Map (service dependencies)
- Failures (exceptions, errors)
- Performance (slow requests)
- Availability (uptime monitoring)

### Log Analytics

Query logs from all services:

```kql
traces
| where timestamp > ago(1h)
| where cloud_RoleName == "auth-service"
| project timestamp, message, severityLevel
| order by timestamp desc
```

### RabbitMQ Management UI

**URL**: `http://rabbitmq-xshopai-{environment}.{region}.azurecontainer.io:15672`  
**Login**: admin / RabbitMQ@{environment}2024!

---

## 🔄 Service Deployment (After Infrastructure)

Once infrastructure is deployed, deploy services:

### Deploy All Services

1. Trigger **each service's** GitHub Actions workflow
2. Or use deployment orchestrator: `deployment/azure/app-service/scripts/deploy.sh`

### Deploy Individual Service

```bash
# Trigger workflow via GitHub CLI
gh workflow run deploy.yml \
  --repo xshopai/auth-service \
  --ref main \
  --field environment=development
```

---

## 🧹 Cleanup

### Delete Development Environment

```bash
az group delete --name rg-xshopai-gh-development --yes --no-wait
```

### Delete Production Environment

**⚠️ WARNING: This is destructive! Requires confirmation.**

```bash
# Manual confirmation required
az group delete --name rg-xshopai-gh-production --yes
```

---

## 📁 Repository Structure

```
infrastructure/
├── .github/
│   └── workflows/
│       └── deploy-app-service-infra.yml  ← GitHub Actions workflow
└── azure/
    └── app-service/
        ├── bicep/
        │   ├── main.bicep                 ← Main orchestrator
        │   └── modules/
        │       ├── monitoring.bicep       ← App Insights + Log Analytics
        │       ├── keyvault.bicep         ← Key Vault
        │       ├── databases.bicep        ← Cosmos, PostgreSQL, MySQL, SQL
        │       ├── redis.bicep            ← Redis Cache
        │       ├── rabbitmq.bicep         ← RabbitMQ Container Instance
        │       └── app-services.bicep     ← 16 App Services
        └── docs/
            └── README.md                  ← This file
```

---

## 🐛 Troubleshooting

### Deployment Fails

1. **Check workflow logs**: GitHub Actions → Workflow run → View logs
2. **Verify secrets exist**: Check GitHub organization secrets
3. **Check Azure permissions**: Service Principal needs Contributor role

### App Services Won't Start

1. **Check container logs**:

   ```bash
   az webapp log tail \
     --resource-group rg-xshopai-gh-dev \
     --name app-auth-service-dev
   ```

2. **Verify ACR credentials**: Check `DOCKER_REGISTRY_SERVER_*` settings
3. **Check Key Vault access**: App Service identity needs Key Vault access

### RabbitMQ Connection Issues

1. **Check ACI status**:

   ```bash
   az container show \
     --resource-group rg-xshopai-gh-dev \
     --name aci-rabbitmq-development
   ```

2. **Verify public IP**: Services must use FQDN, not IP
3. **Check firewall**: Port 5672 must be accessible

---

## 💰 Cost Estimation

### Development Environment

| Resource               | Monthly Cost (USD) |
| ---------------------- | ------------------ |
| App Service Plan (B1)  | ~$13               |
| Cosmos DB (Serverless) | ~$5                |
| PostgreSQL (B1ms)      | ~$12               |
| MySQL (B1s)            | ~$12               |
| SQL Server (Basic)     | ~$15               |
| Redis (Basic C0)       | ~$17               |
| RabbitMQ (ACI)         | ~$45               |
| App Insights           | ~$0 (free tier)    |
| **Total**              | **~$119/month**    |

### Production Environment

| Resource                   | Monthly Cost (USD) |
| -------------------------- | ------------------ |
| App Service Plan (P1v2 x2) | ~$292              |
| Cosmos DB (Serverless)     | ~$20               |
| PostgreSQL (Standard)      | ~$50               |
| MySQL (Standard)           | ~$50               |
| SQL Server (Standard)      | ~$75               |
| Redis (Standard C1)        | ~$75               |
| RabbitMQ (ACI - 2 CPU)     | ~$90               |
| App Insights               | ~$5                |
| **Total**                  | **~$657/month**    |

---

## 🔗 Related Documentation

- [Deployment Overview](../../../deployment/azure/app-service/docs/README.md)
- [Architecture Guide](../../../deployment/azure/app-service/docs/ARCHITECTURE.md)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [App Service Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
