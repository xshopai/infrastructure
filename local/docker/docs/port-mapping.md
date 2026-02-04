# Port Mapping Reference

## Quick Reference

| #   | Service                 | Port | Technology       | Database   | DB Port |
| --- | ----------------------- | ---- | ---------------- | ---------- | ------- |
| 1   | Product Service         | 8001 | Python/FastAPI   | MongoDB    | 27019   |
| 2   | User Service            | 8002 | Node.js/Express  | MongoDB    | 27018   |
| 3   | Admin Service           | 8003 | Node.js/Express  | -          | -       |
| 4   | Auth Service            | 8004 | Node.js/Express  | MongoDB    | 27017   |
| 5   | Inventory Service       | 8005 | Python/FastAPI   | MySQL      | 3306    |
| 6   | Order Service           | 8006 | .NET 8/ASP.NET   | SQL Server | 1434    |
| 7   | Order Processor Service | 8007 | Java/Spring Boot | PostgreSQL | 5435    |
| 8   | Cart Service            | 8008 | Java/Quarkus     | Redis      | 6379    |
| 9   | Payment Service         | 8009 | .NET 8/ASP.NET   | SQL Server | 1433    |
| 10  | Review Service          | 8010 | Node.js/Express  | MongoDB    | 27020   |
| 11  | Notification Service    | 8011 | Node.js/Express  | -          | -       |
| 12  | Audit Service           | 8012 | Node.js/Express  | PostgreSQL | 5434    |
| 13  | Chat Service            | 8013 | Node.js/Express  | -          | -       |
| 14  | Web BFF                 | 8014 | Node.js/TS       | -          | -       |

## Frontend Ports

| Service     | Development | Production (Docker) |
| ----------- | ----------- | ------------------- |
| Customer UI | 3000        | 3000 (nginx:80)     |
| Admin UI    | 3001        | 3001 (nginx:80)     |

## Infrastructure Ports

| Service  | Main Port        | Management Port |
| -------- | ---------------- | --------------- |
| RabbitMQ | 5672 (AMQP)      | 15672 (UI)      |
| Redis    | 6379             | -               |
| Jaeger   | 4317/4318 (OTLP) | 16686 (UI)      |
| Mailpit  | 1025 (SMTP)      | 8025 (UI)       |

## Database Ports

| Database   | Service         | Port  | Container Name                   |
| ---------- | --------------- | ----- | -------------------------------- |
| MongoDB    | Auth            | 27017 | xshopai-auth-mongodb             |
| MongoDB    | User            | 27018 | xshopai-user-mongodb             |
| MongoDB    | Product         | 27019 | xshopai-product-mongodb          |
| MongoDB    | Review          | 27020 | xshopai-review-mongodb           |
| PostgreSQL | Audit           | 5434  | xshopai-audit-postgres           |
| PostgreSQL | Order Processor | 5435  | xshopai-order-processor-postgres |
| SQL Server | Payment         | 1433  | xshopai-payment-sqlserver        |
| SQL Server | Order           | 1434  | xshopai-order-sqlserver          |
| MySQL      | Inventory       | 3306  | xshopai-inventory-mysql          |

## Deployment Scripts

Individual service deployment scripts are located in `modules/services/`:

```
modules/services/
├── _common.sh              # Shared deployment functions
├── auth-service.sh         # Auth Service (Node.js)
├── user-service.sh         # User Service (Node.js)
├── admin-service.sh        # Admin Service (Node.js)
├── review-service.sh       # Review Service (Node.js)
├── audit-service.sh        # Audit Service (Node.js)
├── notification-service.sh # Notification Service (Node.js)
├── chat-service.sh         # Chat Service (Node.js)
├── web-bff.sh              # Web BFF (Node.js/TS)
├── product-service.sh      # Product Service (Python)
├── inventory-service.sh    # Inventory Service (Python)
├── order-service.sh        # Order Service (.NET)
├── payment-service.sh      # Payment Service (.NET)
├── cart-service.sh         # Cart Service (Java/Quarkus)
├── order-processor-service.sh  # Order Processor (Java/Spring)
├── customer-ui.sh          # Customer UI (React)
└── admin-ui.sh             # Admin UI (React)
```

## Container Naming Convention

All containers follow the naming pattern: `xshopai-<service-name>`

Examples:

- `xshopai-product-service`
- `xshopai-user-mongodb`
- `xshopai-rabbitmq`

## Volume Naming Convention

All volumes follow the naming pattern: `xshopai_<service>_<type>_data`

Examples:

- `xshopai_product_mongodb_data`
- `xshopai_audit_postgres_data`
- `xshopai_rabbitmq_data`

## Dapr Sidecar Configuration

When Dapr is enabled (`--dapr` flag), each service gets a companion sidecar:

| Service Container       | Dapr Sidecar Container       | HTTP Port | gRPC Port |
| ----------------------- | ---------------------------- | --------- | --------- |
| xshopai-auth-service    | xshopai-auth-service-dapr    | 3500      | 50001     |
| xshopai-user-service    | xshopai-user-service-dapr    | 3500      | 50001     |
| xshopai-product-service | xshopai-product-service-dapr | 3500      | 50001     |
| ...                     | ...                          | ...       | ...       |
