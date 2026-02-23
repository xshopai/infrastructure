# xshopai Infrastructure

> **One-Stop Infrastructure Repository**: Local development, cloud deployment (Azure), and automation scripts for the xshopai e-commerce platform.

This repository contains everything needed to deploy and run the xshopai platform in any environment:

- 🏠 **Local Development** - Docker Compose for local testing
- ☁️ **Azure Deployment** - Infrastructure as Code (Bicep) + automation scripts
- 🤖 **CI/CD** - GitHub Actions workflows for automated deployments
- 📜 **Scripts** - Bootstrap, setup, and utility scripts

---

## 🚀 Quick Start

### Local Development

```bash
# Start all services locally with Docker Compose
cd local/docker-compose
./start-infra.sh

# Or use Docker scripts
cd local/docker
./deploy.sh
```

### Azure App Service Deployment

```bash
# One-command bootstrap and deployment
cd azure/app-service
./scripts/deploy.sh
```

This will:

1. ✅ Create Azure Service Principal
2. ✅ Create Container Registry
3. ✅ Configure GitHub secrets
4. ✅ Setup GitHub environments
5. ✅ Trigger infrastructure deployment
6. ✅ Deploy all 16 services

**Time:** ~1 hour (10 min hands-on, 50 min automated)

---

## 📁 Repository Structure

```
infrastructure/
├── .github/workflows/
│   └── deploy-app-service-infra.yml    # Infrastructure CI/CD
│
├── azure/
│   ├── app-service/                     # App Service deployment (self-contained)
│   │   ├── bicep/                       # Bicep IaC templates
│   │   │   ├── main.bicep
│   │   │   ├── parameters.*.json
│   │   │   └── modules/
│   │   ├── scripts/                     # All scripts needed for deployment
│   │   │   ├── deploy.sh               # 🎯 Main entry point
│   │   │   ├── azure-setup.sh          # Azure prerequisites
│   │   │   ├── github-setup.sh         # GitHub configuration
│   │   │   ├── health-check.sh         # Verification
│   │   │   └── common.sh               # Shared functions
│   │   └── docs/                        # Deployment guides
│   │
│   └── aca/                             # Container Apps (self-contained alternative)
│       ├── bicep/
│       ├── scripts/
│       └── docs/
│
├── local/
│   ├── docker/                          # Docker-based local dev
│   │   ├── deploy.sh
│   │   ├── stop.sh
│   │   └── modules/
│   └── docker-compose/                  # Docker Compose setup
│       ├── docker-compose.*.yml
│       ├── start-infra.sh
│       └── stop-infra.sh
│
└── shared/                              # Shared configs (service definitions)
    └── services/
        └── services.yaml                # Service metadata
```

---

## 🎯 Deployment Options

### Option 1: Azure App Service (Recommended for Production)

**What you get:**

- 16 App Services (14 microservices + 2 UIs)
- RabbitMQ Container Instance
- 4 Database systems (Cosmos DB, PostgreSQL, MySQL, SQL Server)
- Redis Cache
- Key Vault (with auto-generated secrets)
- Application Insights monitoring

**Quick start:**

```bash
cd azure/app-service
./scripts/deploy.sh
```

**Documentation:** [azure/app-service/docs/README.md](azure/app-service/docs/README.md)

---

### Option 2: Azure Container Apps

**What you get:**

- Serverless container hosting
- Dapr integration
- Auto-scaling
- Service Bus messaging

**Quick start:**

```bash
cd azure/aca/scripts
./deploy.sh
```

**Documentation:** [azure/aca/docs/README.md](azure/aca/docs/README.md)

---

### Option 3: Local Development (Docker)

**What you get:**

- All 16 services running locally
- Local databases (MongoDB, PostgreSQL, MySQL, SQL Server)
- RabbitMQ
- Redis
- Full platform for testing

**Quick start:**

```bash
cd local/docker-compose
./start-infra.sh
```

**Documentation:** [local/docker-compose/README.md](local/docker-compose/README.md)

---

## 🔐 Secrets Management

### Azure Deployment

Secrets are **auto-generated** by the infrastructure workflow:

- JWT RS256 key pair
- Admin password
- Database passwords

View secrets in Azure Key Vault after deployment.

### Local Development

Secrets are in `.env` files (not committed to git).

---

## 🛠️ Available Scripts

### App Service Deployment

| Script            | Purpose                           | Location                     |
| ----------------- | --------------------------------- | ---------------------------- |
| `deploy.sh`       | ⭐ Master bootstrap orchestrator  | `azure/app-service/scripts/` |
| `azure-setup.sh`  | Create Service Principal + ACR    | `azure/app-service/scripts/` |
| `github-setup.sh` | Create GitHub environments        | `azure/app-service/scripts/` |
| `health-check.sh` | Test all service health endpoints | `azure/app-service/scripts/` |
| `common.sh`       | Shared utility functions          | `azure/app-service/scripts/` |

### Local Development

| Script           | Purpose                    | Location                |
| ---------------- | -------------------------- | ----------------------- |
| `start-infra.sh` | Start local infrastructure | `local/docker-compose/` |
| `stop-infra.sh`  | Stop local infrastructure  | `local/docker-compose/` |

> **Note**: Each deployment type is self-contained with all scripts in its own folder.

---

## 📊 CI/CD Workflows

### Infrastructure Workflow

**File:** `.github/workflows/deploy-app-service-infra.yml`

**Triggers:**

- 🔄 **Automatic** - Push to `main` (deploys to dev)
- 👆 **Manual** - Workflow dispatch (choose dev/prod)

**Protection:**

- Development: No approval
- Production: **2 reviewers required**

---

## 💰 Cost Estimates

| Environment    | Monthly Cost (USD) |
| -------------- | ------------------ |
| **Local**      | $0 (your machine)  |
| **Azure Dev**  | ~$119/month        |
| **Azure Prod** | ~$657/month        |

See detailed cost breakdowns in deployment guides.

---

## 📚 Documentation

- **Quick Start**: This README
- **App Service Deployment**: [azure/app-service/docs/README.md](azure/app-service/docs/README.md)
- **Architecture Deep Dive**: [azure/app-service/docs/ARCHITECTURE.md](azure/app-service/docs/ARCHITECTURE.md)
- **Container Apps**: [azure/aca/docs/README.md](azure/aca/docs/README.md)
- **Local Development**: [local/docker-compose/README.md](local/docker-compose/README.md)

---

## 🔄 Migrating from Old Structure

<details>
<summary>If you were using the old <code>deployment</code> repo...</summary>

The `deployment` repo has been **consolidated into `infrastructure`**:

| Old Location                            | New Location                                |
| --------------------------------------- | ------------------------------------------- |
| `deployment/azure/app-service/scripts/` | `infrastructure/azure/app-service/scripts/` |
| `deployment/azure/app-service/docs/`    | `infrastructure/azure/app-service/docs/`    |
| `deployment/local/docker-compose/`      | `infrastructure/local/docker-compose/`      |

**Update your workflows**:

```yaml
# Old
uses: xshopai/deployment/.github/workflows/...

# New
uses: xshopai/infrastructure/.github/workflows/...
```

</details>

---

## 🔧 Troubleshooting

### Services Not Responding After Deployment

**Problem**: Application services fail to start or show "Application Error"

**Common Cause**: Critical infrastructure services (PostgreSQL, RabbitMQ) may be stopped

**Solution**:

```bash
# Check and start all infrastructure services
cd scripts
chmod +x ensure-services-running.sh
./ensure-services-running.sh rg-xshopai-development development
```

Or manually check:

```bash
# Check PostgreSQL state
az postgres flexible-server show \
  --name psql-xshopai-development \
  --resource-group rg-xshopai-development \
  --query "state" -o tsv

# Start if stopped
az postgres flexible-server start \
  --name psql-xshopai-development \
  --resource-group rg-xshopai-development

# Check RabbitMQ state
az container show \
  --name aci-rabbitmq-development \
  --resource-group rg-xshopai-development \
  --query "instanceView.state" -o tsv
```

**Prevention**: 
- Azure Postgres Flexible Server doesn't auto-start - avoid manually stopping it
- Use Azure Monitor alerts to notify when services go down
- Run `ensure-services-running.sh` before deployments

### Application Health Check Failing

If App Service shows "unhealthy" in Azure Portal:
1. Check infrastructure services are running (see above)
2. Verify environment variables are set correctly
3. Check application logs: `az webapp log tail --name <app-name> --resource-group <rg-name>`

---

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/xshopai/infrastructure/issues)
- **Discussions**: [GitHub Discussions](https://github.com/xshopai/infrastructure/discussions)
- **Documentation**: See `docs/` folders in each deployment option

---

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Happy Deploying! 🚀**
