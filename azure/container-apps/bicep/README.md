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
