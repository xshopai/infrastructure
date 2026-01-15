# Dapr Components Configuration

This document explains the Dapr components used in the xshopai platform and how they're configured on Azure Container Apps.

## Overview

Dapr (Distributed Application Runtime) provides building blocks for microservice development:

| Component | Purpose | Azure Backing Service |
|-----------|---------|----------------------|
| **pubsub** | Event-driven messaging | Azure Service Bus Topics |
| **statestore** | State management | Azure Cache for Redis |
| **secret-store** | Secrets management | Azure Key Vault |
| **configstore** | Configuration management | Azure Cache for Redis |

## Component Details

### 1. Pub/Sub Component (`pubsub`)

**Type:** `pubsub.azure.servicebus.topics`

Used for asynchronous event-driven communication between services.

#### Configuration

```bicep
resource daprPubsub 'Microsoft.App/managedEnvironments/daprComponents@2023-05-01' = {
  parent: containerAppsEnvironment
  name: 'pubsub'
  properties: {
    componentType: 'pubsub.azure.servicebus.topics'
    version: 'v1'
    metadata: [
      { name: 'connectionString', secretRef: 'sb-connection-string' }
      { name: 'consumerID', value: '${appId}' }
      { name: 'timeoutInSec', value: '60' }
      { name: 'maxActiveMessages', value: '100' }
      { name: 'maxConcurrentHandlers', value: '10' }
    ]
    scopes: [] // Available to all services
  }
}
```

#### Topics Created

| Topic | Publishers | Subscribers |
|-------|-----------|-------------|
| `user-events` | user-service | notification-service, audit-service |
| `order-events` | order-service | notification-service, inventory-service, audit-service |
| `payment-events` | payment-service | order-service, notification-service, audit-service |
| `inventory-events` | inventory-service | order-service, notification-service |
| `product-events` | product-service | inventory-service, audit-service |
| `cart-events` | cart-service | audit-service |
| `review-events` | review-service | product-service, audit-service |
| `notification-events` | notification-service | - |
| `audit-events` | audit-service | - |

#### Usage in Code

**Publishing:**

```javascript
// Node.js
const daprClient = new DaprClient();

await daprClient.pubsub.publish('pubsub', 'user-events', {
  type: 'user.created',
  data: { userId, email }
});
```

```python
# Python
from dapr.clients import DaprClient

with DaprClient() as client:
    client.publish_event('pubsub', 'product-events', {
        'type': 'product.created',
        'data': {'productId': product_id}
    })
```

```java
// Java
@Autowired
private DaprClient daprClient;

daprClient.publishEvent("pubsub", "cart-events", 
    Map.of("type", "cart.updated", "data", cartData)).block();
```

**Subscribing:**

```javascript
// Express subscription route
app.post('/dapr/subscribe', (req, res) => {
  res.json([
    {
      pubsubname: 'pubsub',
      topic: 'order-events',
      route: '/events/order'
    }
  ]);
});

app.post('/events/order', (req, res) => {
  const event = req.body;
  console.log('Received order event:', event);
  res.sendStatus(200);
});
```

### 2. State Store Component (`statestore`)

**Type:** `state.redis`

Used for storing application state (sessions, caches, shopping carts).

#### Configuration

```bicep
resource daprStateStore 'Microsoft.App/managedEnvironments/daprComponents@2023-05-01' = {
  parent: containerAppsEnvironment
  name: 'statestore'
  properties: {
    componentType: 'state.redis'
    version: 'v1'
    metadata: [
      { name: 'redisHost', value: '${redisHost}:6380' }
      { name: 'redisPassword', secretRef: 'redis-password' }
      { name: 'enableTLS', value: 'true' }
      { name: 'actorStateStore', value: 'true' }
    ]
    scopes: ['cart-service', 'auth-service', 'user-service']
  }
}
```

#### Usage in Code

**Save State:**

```javascript
await daprClient.state.save('statestore', [
  {
    key: `cart-${userId}`,
    value: cartData
  }
]);
```

**Get State:**

```javascript
const cart = await daprClient.state.get('statestore', `cart-${userId}`);
```

**Delete State:**

```javascript
await daprClient.state.delete('statestore', `cart-${userId}`);
```

### 3. Secret Store Component (`secret-store`)

**Type:** `secretstores.azure.keyvault`

Used for accessing secrets stored in Azure Key Vault.

#### Configuration

```bicep
resource daprSecretStore 'Microsoft.App/managedEnvironments/daprComponents@2023-05-01' = {
  parent: containerAppsEnvironment
  name: 'secret-store'
  properties: {
    componentType: 'secretstores.azure.keyvault'
    version: 'v1'
    metadata: [
      { name: 'vaultName', value: keyVaultName }
      { name: 'azureClientId', value: managedIdentityClientId }
    ]
    scopes: [] // Available to all services
  }
}
```

#### Secrets Stored

| Secret Name | Purpose | Used By |
|-------------|---------|---------|
| `MONGODB-CONNECTION-STRING` | Cosmos DB connection | user, product, review services |
| `POSTGRESQL-CONNECTION-STRING` | PostgreSQL connection | order, payment, inventory services |
| `REDIS-PASSWORD` | Redis authentication | All services |
| `JWT-SECRET` | JWT signing key | auth-service |
| `STRIPE-API-KEY` | Payment processing | payment-service |
| `SENDGRID-API-KEY` | Email sending | notification-service |

#### Usage in Code

```javascript
// Get single secret
const secret = await daprClient.secret.get('secret-store', 'JWT-SECRET');
const jwtSecret = secret['JWT-SECRET'];

// Get bulk secrets
const secrets = await daprClient.secret.getBulk('secret-store');
```

### 4. Configuration Store Component (`configstore`)

**Type:** `configuration.redis`

Used for dynamic runtime configuration.

#### Configuration

```bicep
resource daprConfigStore 'Microsoft.App/managedEnvironments/daprComponents@2023-05-01' = {
  parent: containerAppsEnvironment
  name: 'configstore'
  properties: {
    componentType: 'configuration.redis'
    version: 'v1'
    metadata: [
      { name: 'redisHost', value: '${redisHost}:6380' }
      { name: 'redisPassword', secretRef: 'redis-password' }
      { name: 'enableTLS', value: 'true' }
    ]
    scopes: []
  }
}
```

#### Usage in Code

```javascript
// Get configuration
const config = await daprClient.configuration.get('configstore', ['feature-flags', 'rate-limits']);

// Subscribe to configuration changes
const unsubscribe = await daprClient.configuration.subscribe(
  'configstore',
  ['feature-flags'],
  (items) => {
    console.log('Configuration changed:', items);
  }
);
```

## Service Invocation

Dapr enables direct service-to-service calls without service discovery complexity.

```javascript
// Call another service
const response = await daprClient.invoker.invoke(
  'user-service',      // App ID
  'users/123',         // Method/endpoint
  HttpMethod.GET
);

// POST with body
const response = await daprClient.invoker.invoke(
  'order-service',
  'orders',
  HttpMethod.POST,
  { items: [...], userId: '123' }
);
```

## Local Development

For local development, use RabbitMQ and local Redis instead of Azure services.

### docker-compose.yml

```yaml
version: '3.8'
services:
  rabbitmq:
    image: rabbitmq:3-management
    ports:
      - "5672:5672"
      - "15672:15672"
      
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
      
  mongodb:
    image: mongo:7
    ports:
      - "27017:27017"
      
  postgres:
    image: postgres:16
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: postgres
```

### Local Dapr Components

Create `.dapr/components/` in your service:

**pubsub.yaml:**
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
```

**statestore.yaml:**
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
```

**secret-store.yaml:**
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: secret-store
spec:
  type: secretstores.local.file
  version: v1
  metadata:
    - name: secretsFile
      value: ".dapr/secrets.json"
```

### Run with Dapr

```bash
dapr run --app-id my-service --app-port 3000 --dapr-http-port 3500 \
  --components-path ./.dapr/components -- npm start
```

## Debugging

### View Dapr Logs

```bash
# In Azure Container Apps
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-dev \
  --type system

# Local development
dapr run --log-level debug ...
```

### Test Pub/Sub

```bash
# Publish event via Dapr HTTP API
curl -X POST http://localhost:3500/v1.0/publish/pubsub/user-events \
  -H "Content-Type: application/json" \
  -d '{"type":"user.created","data":{"userId":"123"}}'
```

### Test State Store

```bash
# Save state
curl -X POST http://localhost:3500/v1.0/state/statestore \
  -H "Content-Type: application/json" \
  -d '[{"key":"test","value":"hello"}]'

# Get state
curl http://localhost:3500/v1.0/state/statestore/test
```

## Best Practices

1. **Use Scopes** - Limit component access to services that need them
2. **Handle Failures** - Implement retry logic and dead-letter queues
3. **Structured Events** - Use consistent event schema across services
4. **State Keys** - Use prefixed keys to avoid collisions
5. **Secret Rotation** - Use Key Vault's rotation features
6. **Observability** - Enable Dapr tracing for distributed request tracking

## Resources

- [Dapr Documentation](https://docs.dapr.io/)
- [Dapr on Azure Container Apps](https://docs.microsoft.com/azure/container-apps/dapr-overview)
- [Dapr Component Reference](https://docs.dapr.io/reference/components-reference/)
