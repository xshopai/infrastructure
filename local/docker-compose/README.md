# xshopai Local Infrastructure

This directory contains Docker Compose configurations for running all infrastructure services locally.

## 📦 What's Included

### Infrastructure Services (`docker-compose.infrastructure.yml`)

- **RabbitMQ** - Message broker for event-driven communication
  - AMQP Port: `5672`
  - Management UI: `http://localhost:15672` (admin/admin123)
- **Zipkin** - Distributed tracing
  - UI & API: `http://localhost:9411`
- **Mailpit** - Email testing server
  - SMTP: `localhost:1025`
  - Web UI: `http://localhost:8025`

### Database Services (`docker-compose.databases.yml`)

**MongoDB Instances:**

- User Service: `localhost:27018` (admin/admin123)
- Product Service: `localhost:27019` (admin/admin123)
- Review Service: `localhost:27020` (admin/admin123)
- Auth Service: `localhost:27021` (admin/admin123)

**PostgreSQL Instances:**

- Audit Service: `localhost:5434` (admin/admin123)
- Order Processor: `localhost:5435` (postgres/postgres)

**SQL Server Instances:**

- Order Service: `localhost:1434` (sa/Admin123!)
- Payment Service: `localhost:1433` (sa/Admin123!)

**MySQL Instance:**

- Inventory Service: `localhost:3306` (admin/admin123)

## 🚀 Quick Start

### Option 1: Use Helper Scripts (Recommended)

```bash
# Start all infrastructure + databases
./start-infra.sh

# Stop all infrastructure + databases
./stop-infra.sh
```

### Option 2: Manual Docker Compose Commands

```bash
# Start infrastructure only
docker-compose -f docker-compose.infrastructure.yml up -d

# Start databases only
docker-compose -f docker-compose.databases.yml up -d

# Start both
docker-compose -f docker-compose.infrastructure.yml -f docker-compose.databases.yml up -d

# Stop services
docker-compose -f docker-compose.infrastructure.yml down
docker-compose -f docker-compose.databases.yml down

# Stop and remove volumes (⚠️ deletes all data)
docker-compose -f docker-compose.infrastructure.yml down --volumes
docker-compose -f docker-compose.databases.yml down --volumes
```

## 📊 Accessing Services

After starting infrastructure with `./start-infra.sh`, you can access:

| Service             | URL                    | Credentials    |
| ------------------- | ---------------------- | -------------- |
| RabbitMQ Management | http://localhost:15672 | admin/admin123 |
| Zipkin Tracing      | http://localhost:9411  | -              |
| Mailpit Email UI    | http://localhost:8025  | -              |

## 🔍 Monitoring & Troubleshooting

### View Logs

```bash
# All infrastructure services
docker-compose -f docker-compose.infrastructure.yml logs -f

# Specific service
docker-compose -f docker-compose.infrastructure.yml logs -f rabbitmq
docker-compose -f docker-compose.infrastructure.yml logs -f zipkin

# All databases
docker-compose -f docker-compose.databases.yml logs -f

# Specific database
docker-compose -f docker-compose.databases.yml logs -f user-mongodb
```

### Check Service Status

```bash
docker-compose -f docker-compose.infrastructure.yml ps
docker-compose -f docker-compose.databases.yml ps
```

### Restart a Service

```bash
docker-compose -f docker-compose.infrastructure.yml restart rabbitmq
docker-compose -f docker-compose.databases.yml restart user-mongodb
```

## 🗄️ Data Persistence

All data is stored in named Docker volumes:

- `rabbitmq_data` - RabbitMQ message queues
- `user_mongodb_data` - User service data
- `product_mongodb_data` - Product service data
- `review_mongodb_data` - Review service data
- `auth_mongodb_data` - Auth service data
- `audit_postgres_data` - Audit service data
- `order_processor_postgres_data` - Order processor data
- `order_sqlserver_data` - Order service data
- `payment_sqlserver_data` - Payment service data
- `inventory_mysql_data` - Inventory service data

### Backup Volumes

```bash
# List volumes
docker volume ls | grep xshopai

# Backup a volume (example: user-mongodb)
docker run --rm -v user_mongodb_data:/data -v $(pwd):/backup alpine tar czf /backup/user-mongodb-backup.tar.gz /data
```

### Remove All Data

```bash
# ⚠️ WARNING: This deletes all data permanently!
docker-compose -f docker-compose.infrastructure.yml down --volumes
docker-compose -f docker-compose.databases.yml down --volumes
```

## 🔗 Integration with Services

After starting infrastructure, you can run services locally:

### Using Dapr (Recommended)

```bash
cd ../../scripts
./dapr.sh  # Starts all services with Dapr
```

### Without Dapr (Development Only)

```bash
cd ../../scripts
./local.sh  # Starts services without Dapr (limited functionality)
```

### Individual Service

```bash
cd ../../../<service-name>
./scripts/dapr.sh   # With Dapr
./scripts/local.sh  # Without Dapr
```

## 🐛 Common Issues

### Port Already in Use

If you see "port already allocated" errors:

```bash
# Check what's using the port (example: 5672)
lsof -i :5672  # macOS/Linux
netstat -ano | findstr :5672  # Windows

# Stop conflicting services or change port in docker-compose file
```

### Container Won't Start

```bash
# Remove container and try again
docker-compose -f docker-compose.infrastructure.yml down
docker-compose -f docker-compose.infrastructure.yml up -d

# View detailed logs
docker-compose -f docker-compose.infrastructure.yml logs <service-name>
```

### Database Connection Issues

1. Ensure databases are running: `docker ps`
2. Check service logs: `docker logs <container-name>`
3. Verify credentials match your service `.env` files
4. Try restarting the database container

## 📝 Configuration Files

- `docker-compose.infrastructure.yml` - Shared infrastructure services
- `docker-compose.databases.yml` - Database services
- `otel-collector-config.yaml` - OpenTelemetry configuration (if using OTEL)

## 🔄 Development Workflow

Typical workflow for local development:

1. **Start infrastructure** (once per session)

   ```bash
   ./start-infra.sh
   ```

2. **Run services** (as needed)

   ```bash
   cd ../../scripts
   ./dapr.sh  # or ./local.sh for no-Dapr mode
   ```

3. **Develop & test** your service changes

4. **Stop services** when done
   ```bash
   ./stop-infra.sh  # or Ctrl+C in service terminals
   ```

## 🌐 Network

All services run on the `xshopai-network` bridge network, allowing them to communicate using service names as hostnames.

Example: From any service, you can connect to:

- `rabbitmq:5672` (RabbitMQ)
- `user-mongodb:27017` (User MongoDB)
- `zipkin:9411` (Zipkin)

## 📚 Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [RabbitMQ Management UI Guide](https://www.rabbitmq.com/management.html)
- [Zipkin Documentation](https://zipkin.io/)
- [Mailpit Documentation](https://github.com/axllent/mailpit)
