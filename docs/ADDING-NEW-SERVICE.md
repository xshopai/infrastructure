# Adding a New Service

This guide explains how to add a new microservice to the xshopai platform.

## Overview

Adding a new service involves:

1. Defining the service in `shared/services/services.yaml`
2. Creating the service repository with standard structure
3. Configuring CI/CD for Container App deployment
4. Optional: Adding new Dapr components or database

## Step 1: Define Service in services.yaml

Edit `shared/services/services.yaml`:

```yaml
services:
  # ... existing services ...
  
  my-new-service:
    name: "my-new-service"
    displayName: "My New Service"
    description: "Description of what this service does"
    
    # Container configuration
    port: 3000
    healthCheckPath: "/health"
    
    # Dapr configuration
    dapr:
      enabled: true
      appId: "my-new-service"
      appPort: 3000
      
    # Resource allocation
    resources:
      dev:
        cpu: "0.25"
        memory: "0.5Gi"
        minReplicas: 0
        maxReplicas: 1
      staging:
        cpu: "0.5"
        memory: "1.0Gi"
        minReplicas: 1
        maxReplicas: 3
      prod:
        cpu: "1.0"
        memory: "2.0Gi"
        minReplicas: 2
        maxReplicas: 10
    
    # Database (if needed)
    database:
      type: "mongodb"  # or "postgresql"
      name: "mynewdb"
    
    # Pub/Sub topics (if needed)
    pubsub:
      publishes:
        - "mynew.created"
        - "mynew.updated"
      subscribes:
        - "order.completed"
```

## Step 2: Create Service Repository

### Standard Structure

```
my-new-service/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── src/
│   └── ...
├── tests/
│   └── ...
├── .dapr/
│   └── components/         # Local Dapr components
│       ├── pubsub.yaml
│       └── statestore.yaml
├── Dockerfile
├── package.json            # or pom.xml, requirements.txt, etc.
├── README.md
├── run.sh
└── run.ps1
```

### Dockerfile Template

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Runtime stage
FROM node:20-alpine
WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy dependencies and source
COPY --from=builder /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs src/ ./src/

USER nodejs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "src/server.js"]
```

### Health Check Endpoint

Your service MUST expose a health check endpoint:

```javascript
// Express.js example
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: 'my-new-service',
    timestamp: new Date().toISOString()
  });
});

// Ready endpoint (optional but recommended)
app.get('/health/ready', async (req, res) => {
  try {
    // Check dependencies (database, external services)
    await checkDatabaseConnection();
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});
```

## Step 3: Create CI/CD Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Azure Container Apps

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - staging
          - prod

env:
  SERVICE_NAME: my-new-service
  CONTAINER_PORT: 3000
  HEALTH_CHECK_PATH: /health

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment || 'dev' }}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set environment variables
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "ENVIRONMENT=${{ github.event.inputs.environment }}" >> $GITHUB_ENV
          else
            echo "ENVIRONMENT=dev" >> $GITHUB_ENV
          fi
          
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          
      - name: Get infrastructure outputs
        id: infra
        run: |
          RG="rg-xshopai-${{ env.ENVIRONMENT }}"
          
          ACR_NAME=$(az deployment group show \
            --resource-group $RG \
            --name main \
            --query properties.outputs.containerRegistryName.value -o tsv)
          ACR_SERVER=$(az deployment group show \
            --resource-group $RG \
            --name main \
            --query properties.outputs.containerRegistryLoginServer.value -o tsv)
          CAE_NAME=$(az deployment group show \
            --resource-group $RG \
            --name main \
            --query properties.outputs.containerAppsEnvironmentName.value -o tsv)
          IDENTITY_ID=$(az deployment group show \
            --resource-group $RG \
            --name main \
            --query properties.outputs.managedIdentityId.value -o tsv)
            
          echo "acr_name=$ACR_NAME" >> $GITHUB_OUTPUT
          echo "acr_server=$ACR_SERVER" >> $GITHUB_OUTPUT
          echo "cae_name=$CAE_NAME" >> $GITHUB_OUTPUT
          echo "identity_id=$IDENTITY_ID" >> $GITHUB_OUTPUT
          echo "resource_group=$RG" >> $GITHUB_OUTPUT
          
      - name: Login to ACR
        run: |
          az acr login --name ${{ steps.infra.outputs.acr_name }}
          
      - name: Build and push image
        run: |
          IMAGE="${{ steps.infra.outputs.acr_server }}/${{ env.SERVICE_NAME }}:${{ github.sha }}"
          docker build -t $IMAGE .
          docker push $IMAGE
          echo "IMAGE=$IMAGE" >> $GITHUB_ENV
          
      - name: Deploy Container App
        run: |
          az deployment group create \
            --resource-group ${{ steps.infra.outputs.resource_group }} \
            --template-file ../infrastructure/azure/container-apps/bicep/modules/container-app.bicep \
            --parameters \
              name="ca-${{ env.SERVICE_NAME }}" \
              environment="${{ env.ENVIRONMENT }}" \
              containerAppsEnvironmentId="/subscriptions/${{ secrets.AZURE_SUBSCRIPTION_ID }}/resourceGroups/${{ steps.infra.outputs.resource_group }}/providers/Microsoft.App/managedEnvironments/${{ steps.infra.outputs.cae_name }}" \
              managedIdentityId="${{ steps.infra.outputs.identity_id }}" \
              containerRegistryServer="${{ steps.infra.outputs.acr_server }}" \
              containerImage="${{ env.IMAGE }}" \
              containerPort=${{ env.CONTAINER_PORT }} \
              healthCheckPath="${{ env.HEALTH_CHECK_PATH }}" \
              daprEnabled=true \
              daprAppId="${{ env.SERVICE_NAME }}"
              
      - name: Get deployment URL
        run: |
          URL=$(az containerapp show \
            --name "ca-${{ env.SERVICE_NAME }}" \
            --resource-group ${{ steps.infra.outputs.resource_group }} \
            --query properties.configuration.ingress.fqdn -o tsv)
          echo "🚀 Deployed to: https://$URL"
```

## Step 4: Add Database (If Needed)

### MongoDB (Cosmos DB)

If your service needs MongoDB, add the database to the infrastructure:

1. Edit `azure/container-apps/bicep/modules/cosmos-db.bicep`:

```bicep
// Add to databases array
var databases = [
  // ... existing databases ...
  {
    name: 'mynewdb'
    collections: [
      { name: 'items', partitionKey: '/id' }
      { name: 'history', partitionKey: '/itemId' }
    ]
  }
]
```

2. Redeploy infrastructure

### PostgreSQL

If your service needs PostgreSQL:

1. Edit `azure/container-apps/bicep/modules/postgresql.bicep`:

```bicep
// Add to databases array
var databases = [
  // ... existing databases ...
  { name: 'mynewdb' }
]
```

2. Redeploy infrastructure

## Step 5: Add Pub/Sub Topics (If Needed)

If your service publishes new event topics:

1. Edit `azure/container-apps/bicep/modules/service-bus.bicep`:

```bicep
// Add to topics array
var topics = [
  // ... existing topics ...
  {
    name: 'mynew-created'
    subscriptions: ['notification-service', 'audit-service']
  }
  {
    name: 'mynew-updated'
    subscriptions: ['search-service', 'audit-service']
  }
]
```

2. Redeploy infrastructure

## Step 6: Local Development Setup

Create local Dapr components in `.dapr/components/`:

### pubsub.yaml

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
spec:
  type: pubsub.rabbitmq
  version: v1
  metadata:
    - name: host
      value: "amqp://localhost:5672"
    - name: durable
      value: "true"
```

### statestore.yaml

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: "localhost:6379"
    - name: redisPassword
      value: ""
```

### Run Locally

```bash
# Start dependencies
docker-compose up -d

# Run with Dapr
dapr run --app-id my-new-service --app-port 3000 --dapr-http-port 3500 \
  --components-path ./.dapr/components -- npm start
```

## Checklist

- [ ] Service defined in `shared/services/services.yaml`
- [ ] Service repository created with standard structure
- [ ] Dockerfile with health check
- [ ] Health check endpoint implemented
- [ ] CI/CD workflow created
- [ ] Database added (if needed)
- [ ] Pub/Sub topics added (if needed)
- [ ] Local Dapr components configured
- [ ] README documented
- [ ] Tested locally with Dapr
- [ ] Successfully deployed to dev environment
