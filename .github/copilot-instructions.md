# Copilot Instructions — infrastructure

## Repository Identity

- **Name**: infrastructure
- **Purpose**: Infrastructure as Code (IaC) — Bicep templates, deployment scripts, and documentation for Azure deployments
- **Language**: Bicep (ARM DSL) + Bash scripts + PowerShell
- **Target Platforms**: Azure App Service, Azure Container Apps (ACA), Docker local

## Architecture

- **Pattern**: IaC repository — declarative Bicep modules for Azure resources, imperative bash scripts for ACA
- **Deployment Targets**:
  - `app-service/` — Azure App Service (Bicep modules)
  - `app-service-docker/` — Azure App Service with Docker containers (Bicep)
  - `aca/` — Azure Container Apps (bash scripts)
  - `local/` — Local Docker Compose orchestration
- **CI/CD**: GitHub Actions workflows in `.github/workflows/`

## Project Structure

```
infrastructure/
├── app-service/
│   ├── bicep/
│   │   ├── main.bicep           # Root orchestration template
│   │   ├── parameters/          # Parameter files per environment
│   │   └── modules/             # Modular Bicep files per resource
│   └── docs/                    # App Service deployment docs
├── app-service-docker/
│   ├── bicep/                   # Docker-based App Service Bicep
│   └── docs/
├── aca/
│   ├── bash/                    # ACA deployment scripts
│   └── docs/                    # ACA deployment docs
├── local/                       # Local dev Docker Compose
├── scripts/                     # Shared utility scripts
├── .github/workflows/           # CI/CD pipelines
└── README.md
```

## Code Conventions

- **Bicep**: Use modular design — one module per Azure resource type
- **Naming**: `main.bicep` as orchestrator, `modules/*.bicep` for individual resources
- **Parameters**: Environment-specific parameter files in `parameters/` directory
- **Bash scripts**: Use `set -euo pipefail` for strict error handling
- **Documentation**: Each deployment target has its own `docs/` folder with step-by-step guides
- Tags on all Azure resources: `environment`, `project`, `managedBy`

## Azure Resources

The platform deploys these Azure services:

- Azure App Service / Container Apps (16 services + 2 UIs)
- Azure Container Registry (ACR)
- Azure Service Bus or RabbitMQ container
- Azure Cache for Redis
- Azure Database for MySQL, PostgreSQL
- Azure SQL Database
- Azure Cosmos DB for MongoDB
- Azure Key Vault
- Azure Application Insights
- Azure Log Analytics Workspace

## Key Patterns

- **Modular Bicep**: Each service has its own module for App Service plan, web app, and configuration
- **OIDC Authentication**: GitHub Actions use OpenID Connect for Azure deployments (no stored secrets)
- **Environment separation**: dev / staging / production via parameter files
- **Secret management**: Azure Key Vault for connection strings and API keys

## Security Rules

- Secret values MUST NOT be hardcoded in Bicep templates — use Azure Key Vault references or secure parameter files
- GitHub Actions deployments MUST use OIDC (OpenID Connect) for Azure authentication — never store long-lived Azure credentials as repository secrets
- All Azure resources MUST have `tags` applied for environment, project, and cost governance
- Connection strings and API keys MUST NOT appear in Bicep `outputs` — consuming services retrieve them from Key Vault
- Parameter files for production (`prod.bicepparam`) MUST NOT be committed with real secrets

## Non-Goals

- This repository does NOT contain application source code — only infrastructure definitions
- This repository does NOT manage runtime service configuration — use Dapr components, App Service configuration, or ACA secrets
- This repository does NOT contain test data or database migrations — handled by db-seeder and individual service migrations
- IaC templates MUST NOT include hardcoded environment-specific values — always use parameter files for environment separation

## Common Commands

```bash
# App Service deployment
az deployment group create --resource-group <rg> --template-file app-service/bicep/main.bicep --parameters app-service/bicep/parameters/dev.bicepparam

# ACA deployment
cd aca/bash && ./deploy.sh

# Local development
cd local && docker compose up -d
```
