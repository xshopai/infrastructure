# Azure Container Apps Deployment Workflows

This directory contains reusable and service-specific workflows for deploying microservices to Azure Container Apps.

## Workflows Overview

| Workflow | Purpose | Trigger |
|----------|---------|---------|
| `reusable-deploy-container-app.yml` | Reusable workflow for any service | Called by other workflows |
| `azure-container-apps-layered-deploy.yml` | Deploy infrastructure (4 layers) | Manual |
| `azure-container-apps-destroy.yml` | Destroy all infrastructure | Manual |
| `validate-bicep.yml` | Validate Bicep files | PR, Push |

## Using the Reusable Deployment Workflow

### Quick Start

Create a workflow file in your service repository at `.github/workflows/deploy.yml`:

```yaml
name: Deploy My Service

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'dev'
        type: choice
        options: [dev, staging, prod]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: my-service
      environment: ${{ github.event.inputs.environment || 'dev' }}
      container_port: 8080
      dapr_enabled: true
    secrets: inherit
```

### Input Parameters

#### Required Inputs

| Input | Type | Description |
|-------|------|-------------|
| `service_name` | string | Name of the service (e.g., `customer-ui`, `user-service`) |
| `environment` | string | Target environment: `dev`, `staging`, or `prod` |

#### Optional Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `dockerfile_path` | string | `Dockerfile` | Path to Dockerfile relative to context |
| `docker_context` | string | `.` | Docker build context path |
| `docker_target` | string | `production` | Docker build target stage |
| `container_port` | number | `8080` | Port the container listens on |
| `cpu` | string | `0.25` | CPU cores (0.25, 0.5, 1, 2, 4) |
| `memory` | string | `0.5Gi` | Memory allocation |
| `min_replicas` | number | `0` | Minimum replicas (0 = scale to zero) |
| `max_replicas` | number | `3` | Maximum replicas |
| `ingress_enabled` | boolean | `true` | Enable HTTP ingress |
| `ingress_external` | boolean | `true` | External (internet) or internal only |
| `health_probe_path` | string | `/health` | Health check endpoint |
| `dapr_enabled` | boolean | `false` | Enable Dapr sidecar |
| `dapr_app_protocol` | string | `http` | Dapr protocol (http/grpc) |
| `dapr_app_port` | number | `8080` | Port for Dapr communication |
| `env_vars` | string | `[]` | Environment variables (JSON array) |
| `secrets` | string | `[]` | Key Vault secrets (JSON array) |
| `image_tag` | string | `''` | Override image tag (default: git SHA) |

### Outputs

| Output | Description |
|--------|-------------|
| `fqdn` | Fully qualified domain name |
| `revision_name` | Deployed revision name |
| `image` | Full image name with tag |

## Service Configuration Examples

### Frontend Service (React/Angular/Vue)

```yaml
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: customer-ui
      environment: dev
      container_port: 8080
      health_probe_path: '/'          # nginx serves index.html at root
      dapr_enabled: false             # Frontend doesn't need Dapr
      min_replicas: 0                 # Scale to zero when idle
      max_replicas: 5
      env_vars: '[{"name": "REACT_APP_API_URL", "value": "https://api.example.com"}]'
    secrets: inherit
```

### Backend Service (Node.js)

```yaml
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: user-service
      environment: dev
      container_port: 3000
      health_probe_path: '/api/health'
      dapr_enabled: true              # Enable Dapr for pub/sub and state
      dapr_app_port: 3000
      cpu: '0.5'
      memory: '1Gi'
      env_vars: '[
        {"name": "NODE_ENV", "value": "production"},
        {"name": "LOG_LEVEL", "value": "info"}
      ]'
    secrets: inherit
```

### Backend Service (Python FastAPI)

```yaml
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: product-service
      environment: dev
      container_port: 8000
      health_probe_path: '/health'
      dapr_enabled: true
      dapr_app_port: 8000
      cpu: '0.5'
      memory: '1Gi'
      env_vars: '[
        {"name": "ENVIRONMENT", "value": "production"},
        {"name": "DEBUG", "value": "false"}
      ]'
    secrets: inherit
```

### Backend Service (Java Spring Boot)

```yaml
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: order-service
      environment: dev
      container_port: 8080
      health_probe_path: '/actuator/health'
      dapr_enabled: true
      dapr_app_port: 8080
      cpu: '1'
      memory: '2Gi'
      min_replicas: 1                 # Keep at least 1 running (JVM startup time)
      max_replicas: 5
    secrets: inherit
```

### Backend Service (.NET)

```yaml
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: payment-service
      environment: dev
      container_port: 5000
      health_probe_path: '/health'
      dapr_enabled: true
      dapr_app_port: 5000
      cpu: '0.5'
      memory: '1Gi'
    secrets: inherit
```

## Environment-Specific Configuration

Use conditional expressions for environment-specific settings:

```yaml
jobs:
  deploy:
    uses: xshopai/infrastructure/.github/workflows/reusable-deploy-container-app.yml@main
    with:
      service_name: my-service
      environment: ${{ github.event.inputs.environment }}
      # Production gets more resources
      cpu: ${{ github.event.inputs.environment == 'prod' && '1' || '0.25' }}
      memory: ${{ github.event.inputs.environment == 'prod' && '2Gi' || '0.5Gi' }}
      # Production always has at least 2 replicas
      min_replicas: ${{ github.event.inputs.environment == 'prod' && 2 || 0 }}
      max_replicas: ${{ github.event.inputs.environment == 'prod' && 10 || 3 }}
    secrets: inherit
```

## Required Secrets

Configure these secrets in your GitHub organization or repository:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Service principal client ID for OIDC |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

These secrets enable Azure OIDC authentication (no passwords stored in GitHub).

## Workflow Triggers

### Recommended Trigger Configuration

```yaml
on:
  # Auto-deploy to dev on main branch changes
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'Dockerfile'
      - 'package*.json'  # or requirements.txt, pom.xml, etc.

  # Build check for PRs (no deploy)
  pull_request:
    branches: [main]

  # Manual deployment to any environment
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'dev'
        type: choice
        options: [dev, staging, prod]
```

## Troubleshooting

### Common Issues

1. **Authentication Failure**
   - Ensure OIDC secrets are configured
   - Verify the service principal has Contributor role on the resource group

2. **Image Push Failure**
   - Verify ACR admin credentials are enabled
   - Check ACR name is correct: `xshopaidevvh5yovacr`

3. **Container App Creation Failure**
   - Verify Container Apps Environment exists: `xshopai-dev-cae`
   - Check resource group: `rg-xshopai-dev`

4. **Health Check Failure**
   - Verify health endpoint responds with 200/204
   - Check container port matches target_port
   - Review container logs: `az containerapp logs show --name <app> -g rg-xshopai-dev`

### Useful Commands

```bash
# View container app logs
az containerapp logs show --name customer-ui --resource-group rg-xshopai-dev --follow

# List revisions
az containerapp revision list --name customer-ui --resource-group rg-xshopai-dev

# Check revision status
az containerapp revision show --name <revision> --app customer-ui -g rg-xshopai-dev

# Restart app
az containerapp revision restart --name <revision> --app customer-ui -g rg-xshopai-dev
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions                            │
├──────────────────────┬──────────────────────────────────────┤
│  Service Workflow    │         Reusable Workflow            │
│  (deploy.yml)        │  (reusable-deploy-container-app.yml) │
│                      │                                      │
│  ┌──────────────┐   │   ┌───────────────────────────────┐  │
│  │ Test & Lint  │───┼──►│ Build & Push to ACR           │  │
│  └──────────────┘   │   └───────────────┬───────────────┘  │
│                      │                   │                  │
│                      │   ┌───────────────▼───────────────┐  │
│                      │   │ Deploy to Container Apps      │  │
│                      │   │ - Create/Update App           │  │
│                      │   │ - Configure Ingress           │  │
│                      │   │ - Setup Dapr (if enabled)     │  │
│                      │   └───────────────┬───────────────┘  │
│                      │                   │                  │
│                      │   ┌───────────────▼───────────────┐  │
│                      │   │ Health Check & Notify         │  │
│                      │   └───────────────────────────────┘  │
└──────────────────────┴──────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Container Apps Environment (xshopai-dev-cae)        │   │
│  │                                                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │ customer-ui │  │user-service │  │product-svc  │  │   │
│  │  │   (React)   │  │  (Node.js)  │  │  (Python)   │  │   │
│  │  │             │  │  + Dapr     │  │  + Dapr     │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  │                                                      │   │
│  │  Dapr Components: pubsub, statestore, secretstore   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```
