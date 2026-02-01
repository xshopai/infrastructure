# xshopai Local Docker Deployment

This folder contains scripts to deploy the entire xshopai microservices platform locally using pure Docker commands (no docker-compose). This provides a production-like environment for local development and testing.

## Overview

The local Docker deployment creates all infrastructure, databases, and services needed to run the complete xshopai platform on your local machine. This approach provides:

- **Full Platform Testing**: Test the entire microservices ecosystem locally
- **Production Parity**: Same container images as production deployments
- **Isolated Development**: Each service runs in its own container with dedicated database
- **Easy Debugging**: View logs, restart services, and inspect containers individually

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Docker Network: xshopai-network                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                         Frontend Applications                             │   │
│  │  ┌─────────────────┐    ┌─────────────────┐                              │   │
│  │  │  Customer UI    │    │   Admin UI      │                              │   │
│  │  │  (React :3000)  │    │  (React :3001)  │                              │   │
│  │  └────────┬────────┘    └────────┬────────┘                              │   │
│  └───────────┼──────────────────────┼───────────────────────────────────────┘   │
│              │                      │                                            │
│              ▼                      ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                            API Gateway / BFF                              │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐ │   │
│  │  │                    Web BFF (Node.js :8014)                          │ │   │
│  │  └─────────────────────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                           │
│              ┌───────────────────────┼───────────────────────┐                   │
│              ▼                       ▼                       ▼                   │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                         Backend Microservices                             │   │
│  │                                                                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │ Auth :8004  │  │ User :8002  │  │Product:8001 │  │Inventory:8005│     │   │
│  │  │  (Node.js)  │  │  (Node.js)  │  │  (Python)   │  │  (Python)   │     │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │   │
│  │         │                │                │                │             │   │
│  │         ▼                ▼                ▼                ▼             │   │
│  │     MongoDB          MongoDB          MongoDB           MySQL            │   │
│  │     (:27017)         (:27018)         (:27019)          (:3306)          │   │
│  │                                                                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │ Order :8006 │  │Payment:8009 │  │ Cart :8008  │  │OrderProc:8007│    │   │
│  │  │   (.NET 8)  │  │  (.NET 8)   │  │(Java/Quarkus)│ │(Java/Spring) │    │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │   │
│  │         │                │                │                │             │   │
│  │         ▼                ▼                ▼                ▼             │   │
│  │    SQL Server       SQL Server         Redis          PostgreSQL         │   │
│  │     (:1434)          (:1433)          (:6379)          (:5435)           │   │
│  │                                                                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │Review :8010 │  │ Audit :8012 │  │ Chat :8013  │  │Notif :8011  │     │   │
│  │  │  (Node.js)  │  │  (Node.js)  │  │  (Node.js)  │  │  (Node.js)  │     │   │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────┘  └─────────────┘     │   │
│  │         │                │                                               │   │
│  │         ▼                ▼                                               │   │
│  │     MongoDB          PostgreSQL                                          │   │
│  │     (:27020)          (:5434)                                            │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                           │
│              ┌───────────────────────┼───────────────────────┐                   │
│              ▼                       ▼                       ▼                   │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                         Infrastructure Services                           │   │
│  │                                                                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │   │
│  │  │    RabbitMQ     │  │     Jaeger      │  │    Mailpit      │          │   │
│  │  │ (AMQP :5672)    │  │  (UI :16686)    │  │  (SMTP :1025)   │          │   │
│  │  │ (Mgmt :15672)   │  │ (OTLP :4317/18) │  │  (UI :8025)     │          │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Resources Created

### Infrastructure Services

| Resource | Container Name     | Ports             | Description                            |
| -------- | ------------------ | ----------------- | -------------------------------------- |
| RabbitMQ | `xshopai-rabbitmq` | 5672, 15672       | Message broker for async communication |
| Redis    | `xshopai-redis`    | 6379              | Cache and state store                  |
| Jaeger   | `xshopai-jaeger`   | 16686, 4317, 4318 | Distributed tracing                    |
| Mailpit  | `xshopai-mailpit`  | 1025, 8025        | Email testing server                   |

### Database Instances

| Database   | Container Name                     | Port  | Used By                 |
| ---------- | ---------------------------------- | ----- | ----------------------- |
| MongoDB    | `xshopai-auth-mongodb`             | 27017 | auth-service            |
| MongoDB    | `xshopai-user-mongodb`             | 27018 | user-service            |
| MongoDB    | `xshopai-product-mongodb`          | 27019 | product-service         |
| MongoDB    | `xshopai-review-mongodb`           | 27020 | review-service          |
| PostgreSQL | `xshopai-audit-postgres`           | 5434  | audit-service           |
| PostgreSQL | `xshopai-order-processor-postgres` | 5435  | order-processor-service |
| SQL Server | `xshopai-payment-sqlserver`        | 1433  | payment-service         |
| SQL Server | `xshopai-order-sqlserver`          | 1434  | order-service           |
| MySQL      | `xshopai-inventory-mysql`          | 3306  | inventory-service       |

### Application Services

| Service              | Container Name                    | Port | Technology          | Database   |
| -------------------- | --------------------------------- | ---- | ------------------- | ---------- |
| Web BFF              | `xshopai-web-bff`                 | 8014 | Node.js/TypeScript  | -          |
| Auth Service         | `xshopai-auth-service`            | 8004 | Node.js/Express     | MongoDB    |
| User Service         | `xshopai-user-service`            | 8002 | Node.js/Express     | MongoDB    |
| Admin Service        | `xshopai-admin-service`           | 8003 | Node.js/Express     | -          |
| Product Service      | `xshopai-product-service`         | 8001 | Python/FastAPI      | MongoDB    |
| Inventory Service    | `xshopai-inventory-service`       | 8005 | Python/FastAPI      | MySQL      |
| Order Service        | `xshopai-order-service`           | 8006 | .NET 8/ASP.NET Core | SQL Server |
| Payment Service      | `xshopai-payment-service`         | 8009 | .NET 8/ASP.NET Core | SQL Server |
| Cart Service         | `xshopai-cart-service`            | 8008 | Java 21/Quarkus     | Redis      |
| Order Processor      | `xshopai-order-processor-service` | 8007 | Java/Spring Boot    | PostgreSQL |
| Review Service       | `xshopai-review-service`          | 8010 | Node.js/Express     | MongoDB    |
| Notification Service | `xshopai-notification-service`    | 8011 | Node.js/Express     | -          |
| Audit Service        | `xshopai-audit-service`           | 8012 | Node.js/Express     | PostgreSQL |
| Chat Service         | `xshopai-chat-service`            | 8013 | Node.js/Express     | -          |

### Frontend Applications

| Application | Container Name        | Port | Technology  |
| ----------- | --------------------- | ---- | ----------- |
| Customer UI | `xshopai-customer-ui` | 3000 | React/nginx |
| Admin UI    | `xshopai-admin-ui`    | 3001 | React/nginx |

## Prerequisites

1. **Docker Desktop** (Windows/Mac) or **Docker Engine** (Linux):

   ```bash
   docker --version  # Should be 20.10+
   ```

2. **System Requirements**:
   - **RAM**: Minimum 8GB, Recommended 16GB+
   - **Disk**: At least 20GB free space
   - **CPU**: 4+ cores recommended

3. **Git Bash** (Windows) or **Bash** (Linux/macOS):

   ```bash
   bash --version
   ```

4. **Docker Resource Settings** (Docker Desktop):
   - Memory: 8GB minimum (16GB recommended)
   - CPUs: 4 minimum
   - Disk: 50GB+

## Usage

### Quick Start

```bash
cd infrastructure/local/docker

# Deploy everything
./deploy.sh

# Check status
./status.sh

# Access the platform
# Customer UI: http://localhost:3000
# Admin UI: http://localhost:3001
```

### Deployment Options

#### Full Deployment

```bash
# Deploy all components (default)
./deploy.sh

# Deploy with clean start (removes existing containers/volumes first)
./deploy.sh --clean

# Deploy without rebuilding images (faster)
./deploy.sh --skip-build
```

#### Partial Deployment

```bash
# Deploy only infrastructure (RabbitMQ, Redis, Jaeger, Mailpit)
./deploy.sh --infra-only

# Deploy only databases (MongoDB, PostgreSQL, SQL Server, MySQL)
./deploy.sh --db-only

# Deploy only application services (requires databases running)
./deploy.sh --services-only

# Deploy only frontend applications
./deploy.sh --frontends-only
```

#### Combining Options

```bash
# Clean deployment with infrastructure and databases only
./deploy.sh --clean --infra-only
./deploy.sh --db-only

# Deploy services without rebuilding
./deploy.sh --services-only --skip-build
```

## Deployment Time

| Component            | Containers | Estimated Time       |
| -------------------- | ---------- | -------------------- |
| Network              | 1          | ~5 seconds           |
| Infrastructure       | 4          | ~30 seconds          |
| MongoDB Databases    | 4          | ~30 seconds          |
| PostgreSQL Databases | 2          | ~20 seconds          |
| SQL Server Databases | 2          | ~60-90 seconds       |
| MySQL Database       | 1          | ~30-60 seconds       |
| Node.js Services     | 8          | ~2-3 minutes (build) |
| Python Services      | 2          | ~1-2 minutes (build) |
| .NET Services        | 2          | ~2-3 minutes (build) |
| Java Services        | 2          | ~3-4 minutes (build) |
| Frontend Apps        | 2          | ~2-3 minutes (build) |

**Total First Deployment**: ~15-20 minutes (includes image builds)
**Subsequent Deployments (skip-build)**: ~3-5 minutes

## Naming Conventions

### Container Names

```
xshopai-{service-name}
```

Examples: `xshopai-product-service`, `xshopai-user-mongodb`, `xshopai-rabbitmq`

### Volume Names

```
xshopai_{service}_{type}_data
```

Examples: `xshopai_product_mongodb_data`, `xshopai_rabbitmq_data`

### Image Names

```
xshopai/{service-name}:{tag}
```

Examples: `xshopai/product-service:latest`, `xshopai/customer-ui:latest`

## Environment Variables & Credentials

### Default Credentials

| Service                 | Username | Password                | Notes            |
| ----------------------- | -------- | ----------------------- | ---------------- |
| MongoDB (all)           | admin    | admin123                | Root user        |
| PostgreSQL (audit)      | admin    | admin123                | Database user    |
| PostgreSQL (order-proc) | postgres | postgres                | Database user    |
| SQL Server (all)        | sa       | Admin123!               | System admin     |
| MySQL (inventory)       | admin    | admin123                | Application user |
| MySQL (inventory)       | root     | inventory_root_pass_123 | Root user        |
| RabbitMQ                | admin    | admin123                | Management user  |
| Redis                   | -        | redis123                | Password auth    |

### Connection Strings

**MongoDB**:

```
mongodb://admin:admin123@localhost:27017/db_name?authSource=admin
mongodb://admin:admin123@localhost:27018/db_name?authSource=admin
mongodb://admin:admin123@localhost:27019/db_name?authSource=admin
mongodb://admin:admin123@localhost:27020/db_name?authSource=admin
```

**PostgreSQL**:

```
postgresql://admin:admin123@localhost:5434/audit_service_db
postgresql://postgres:postgres@localhost:5435/order_processor_db
```

**SQL Server**:

```
Server=localhost,1433;Database=payment_service_db;User Id=sa;Password=Admin123!;TrustServerCertificate=True
Server=localhost,1434;Database=order_service_db;User Id=sa;Password=Admin123!;TrustServerCertificate=True
```

**MySQL**:

```
mysql://admin:admin123@localhost:3306/inventory_service_db
```

**RabbitMQ**:

```
amqp://admin:admin123@localhost:5672
```

**Redis**:

```
redis://:redis123@localhost:6379
```

## Service Endpoints

### Frontend Applications

| Application | URL                   | Description                     |
| ----------- | --------------------- | ------------------------------- |
| Customer UI | http://localhost:3000 | Customer-facing e-commerce site |
| Admin UI    | http://localhost:3001 | Administration dashboard        |

### API Documentation

| Service           | Swagger/OpenAPI URL           |
| ----------------- | ----------------------------- |
| Product Service   | http://localhost:8001/docs    |
| Inventory Service | http://localhost:8005/docs    |
| Order Service     | http://localhost:8006/swagger |
| Payment Service   | http://localhost:8009/swagger |

### Health Check Endpoints

| Service           | Health URL                   |
| ----------------- | ---------------------------- |
| Auth Service      | http://localhost:8004/health |
| User Service      | http://localhost:8002/health |
| Product Service   | http://localhost:8001/health |
| Inventory Service | http://localhost:8005/health |
| Order Service     | http://localhost:8006/health |
| Payment Service   | http://localhost:8009/health |

### Infrastructure UIs

| Service             | URL                    | Credentials      |
| ------------------- | ---------------------- | ---------------- |
| RabbitMQ Management | http://localhost:15672 | admin / admin123 |
| Jaeger Tracing      | http://localhost:16686 | -                |
| Mailpit Email       | http://localhost:8025  | -                |

## Management Scripts

### Check Status

```bash
# Show status of all containers with health info
./status.sh
```

Output shows:

- Container running state (● running, ○ stopped)
- Health status (healthy, unhealthy)
- Port mappings
- Resource usage summary

### View Logs

```bash
# View logs for a specific service
./logs.sh product-service

# Follow logs in real-time
./logs.sh product-service -f

# Show last N lines
./logs.sh product-service -n 500

# View summary of all container logs
./logs.sh --all
```

### Stop Services

```bash
# Stop all containers
./stop.sh

# Stop only application services (keep infrastructure/DBs)
./stop.sh --services

# Stop only databases
./stop.sh --db

# Stop only infrastructure
./stop.sh --infra

# Stop and remove containers
./stop.sh --remove
```

### Cleanup

```bash
# Remove everything (containers, volumes, network)
./cleanup.sh

# Remove only containers
./cleanup.sh --containers

# Remove only volumes (deletes all data!)
./cleanup.sh --volumes

# Remove only network
./cleanup.sh --network

# Remove built Docker images
./cleanup.sh --images
```

## Debugging Individual Modules

Each deployment module can be run independently for debugging:

```bash
cd modules

# Source common utilities first
source common.sh

# Run specific module
./01-network.sh       # Create network only
./02-infrastructure.sh # Deploy RabbitMQ, Redis, etc.
./03-mongodb.sh       # Deploy MongoDB instances
./04-postgresql.sh    # Deploy PostgreSQL instances
./05-sqlserver.sh     # Deploy SQL Server instances
./06-mysql.sh         # Deploy MySQL instance
./07-nodejs-services.sh   # Deploy Node.js services
./08-python-services.sh   # Deploy Python services
./09-dotnet-services.sh   # Deploy .NET services
./10-java-services.sh     # Deploy Java services
./11-frontends.sh         # Deploy frontend apps
```

## Common Development Tasks

### Restart a Single Service

```bash
# Stop the container
docker stop xshopai-product-service
docker rm xshopai-product-service

# Rebuild and restart
cd modules
source common.sh
BUILD_IMAGES=true
./08-python-services.sh
```

### Connect to Databases

```bash
# MongoDB
docker exec -it xshopai-product-mongodb mongosh -u admin -p admin123

# PostgreSQL
docker exec -it xshopai-audit-postgres psql -U admin -d audit_service_db

# MySQL
docker exec -it xshopai-inventory-mysql mysql -u admin -padmin123 inventory_service_db

# SQL Server
docker exec -it xshopai-payment-sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'Admin123!' -C
```

### Execute Commands in Container

```bash
# Run shell in service container
docker exec -it xshopai-product-service /bin/bash

# Run specific command
docker exec xshopai-product-service python -c "print('hello')"
```

### Check Resource Usage

```bash
# Real-time stats for all xshopai containers
docker stats --filter "name=xshopai-"

# One-time snapshot
docker stats --no-stream --filter "name=xshopai-"
```

### Copy Files To/From Container

```bash
# Copy from container to host
docker cp xshopai-product-service:/app/logs ./local-logs

# Copy from host to container
docker cp ./config.json xshopai-product-service:/app/config.json
```

## Troubleshooting

### Container Won't Start

```bash
# Check container logs
docker logs xshopai-<service-name>

# Check container details and exit code
docker inspect xshopai-<service-name>

# Check if image exists
docker images | grep xshopai

# Rebuild the image
cd /path/to/service
docker build -t xshopai/<service-name>:latest .
```

### Port Already in Use

```bash
# Find process using port (Linux/Mac)
lsof -i :8001
kill -9 <PID>

# Find process using port (Windows)
netstat -ano | findstr :8001
taskkill /PID <PID> /F
```

### Database Connection Issues

1. Check if database container is running:

   ```bash
   ./status.sh
   ```

2. Check database logs:

   ```bash
   docker logs xshopai-<db-name>
   ```

3. Verify network connectivity:

   ```bash
   docker exec xshopai-product-service ping xshopai-product-mongodb
   ```

4. Test database connection from service container:
   ```bash
   docker exec -it xshopai-product-service mongosh \
     mongodb://admin:admin123@xshopai-product-mongodb:27017
   ```

### Out of Memory

1. Check Docker Desktop resource settings
2. Increase memory allocation (16GB recommended)
3. Deploy fewer services:
   ```bash
   ./deploy.sh --infra-only
   ./deploy.sh --db-only
   # Run services locally outside Docker
   ```

### SQL Server Takes Too Long

SQL Server containers can take 60-90 seconds to initialize. This is normal.

```bash
# Check if still initializing
docker logs xshopai-payment-sqlserver --tail 50

# Wait for ready state
docker exec xshopai-payment-sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'Admin123!' -Q "SELECT 1" -C
```

### Image Build Failures

```bash
# Build with verbose output
docker build --progress=plain -t xshopai/<service>:latest .

# Build without cache
docker build --no-cache -t xshopai/<service>:latest .
```

### Network Issues

```bash
# Recreate network
docker network rm xshopai-network
docker network create xshopai-network

# Verify network
docker network inspect xshopai-network
```

## Resource Estimates

### Memory Usage (Approximate)

| Component                 | Memory      |
| ------------------------- | ----------- |
| MongoDB (per instance)    | 200-500 MB  |
| PostgreSQL (per instance) | 100-200 MB  |
| SQL Server (per instance) | 500-1000 MB |
| MySQL                     | 200-400 MB  |
| RabbitMQ                  | 150-300 MB  |
| Redis                     | 50-100 MB   |
| Node.js Service (each)    | 100-300 MB  |
| Python Service (each)     | 100-200 MB  |
| .NET Service (each)       | 150-300 MB  |
| Java Service (each)       | 300-500 MB  |
| Frontend (each)           | 50-100 MB   |

**Total Estimated**: 6-10 GB (with all services running)

### Disk Usage

| Component        | Disk Space               |
| ---------------- | ------------------------ |
| Docker Images    | 5-10 GB                  |
| Database Volumes | 1-5 GB (grows with data) |
| Container Logs   | 100 MB - 1 GB            |

## Comparison with Azure ACA Deployment

| Aspect             | Local Docker           | Azure ACA                               |
| ------------------ | ---------------------- | --------------------------------------- |
| **Environment**    | Local machine          | Azure Cloud                             |
| **Databases**      | Individual containers  | Managed services (Cosmos DB, Azure SQL) |
| **Message Broker** | RabbitMQ               | Azure Service Bus                       |
| **Cache**          | Redis container        | Azure Cache for Redis                   |
| **Identity**       | Static credentials     | Managed Identity                        |
| **Secrets**        | Environment variables  | Azure Key Vault                         |
| **Tracing**        | Jaeger                 | Application Insights                    |
| **Cost**           | Free (local resources) | Pay-per-use                             |
| **Scaling**        | Manual                 | Auto-scaling                            |
| **Use Case**       | Development & Testing  | Production                              |

## Directory Structure

```
infrastructure/local/docker/
├── deploy.sh               # Main deployment orchestrator
├── stop.sh                 # Stop all containers
├── status.sh               # Show container status
├── cleanup.sh              # Remove containers, volumes, network
├── logs.sh                 # View container logs
├── README.md               # Quick reference
├── docs/
│   ├── README.md           # This comprehensive documentation
│   └── port-mapping.md     # Port reference guide
└── modules/
    ├── common.sh           # Shared utilities and functions
    ├── 01-network.sh       # Docker network setup
    ├── 02-infrastructure.sh # RabbitMQ, Redis, Jaeger, Mailpit
    ├── 03-mongodb.sh       # MongoDB instances (4)
    ├── 04-postgresql.sh    # PostgreSQL instances (2)
    ├── 05-sqlserver.sh     # SQL Server instances (2)
    ├── 06-mysql.sh         # MySQL instance (1)
    ├── 07-nodejs-services.sh   # Node.js services (8)
    ├── 08-python-services.sh   # Python services (2)
    ├── 09-dotnet-services.sh   # .NET services (2)
    ├── 10-java-services.sh     # Java services (2)
    └── 11-frontends.sh         # Frontend applications (2)
```

## Related Documentation

- [Azure ACA Deployment](../../../azure/aca/docs/README.md) - Production cloud deployment
- [Docker Compose Setup](../../../../scripts/docker-compose/) - Alternative local deployment
- [Service Documentation](../../../../docs/) - Platform documentation
- [API Specifications](../../../../docs/API.md) - API reference

## Support

For issues with local Docker deployment:

1. Check container logs: `./logs.sh <service-name>`
2. Verify Docker resources: Docker Desktop → Settings → Resources
3. Run status check: `./status.sh`
4. Review this troubleshooting guide
5. Check individual service documentation in their respective repositories
