# Port Mapping Reference

## Service Ports

| #   | Service              | Port | Technology         | Database   | DB Port |
| --- | -------------------- | ---- | ------------------ | ---------- | ------- |
| 1   | Product Service      | 8001 | Python/FastAPI     | MongoDB    | 27019   |
| 2   | User Service         | 8002 | Node.js/Express    | MongoDB    | 27018   |
| 3   | Admin Service        | 8003 | Node.js/Express    | -          | -       |
| 4   | Auth Service         | 8004 | Node.js/Express    | MongoDB    | 27017   |
| 5   | Inventory Service    | 8005 | Python/FastAPI     | MySQL      | 3306    |
| 6   | Order Service        | 8006 | .NET 8/ASP.NET     | SQL Server | 1434    |
| 7   | Order Processor      | 8007 | Java/Spring Boot   | PostgreSQL | 5435    |
| 8   | Cart Service         | 8008 | Java/Quarkus       | Redis      | 6379    |
| 9   | Payment Service      | 8009 | .NET 8/ASP.NET     | SQL Server | 1433    |
| 10  | Review Service       | 8010 | Node.js/Express    | MongoDB    | 27020   |
| 11  | Notification Service | 8011 | Node.js/Express    | -          | -       |
| 12  | Audit Service        | 8012 | Node.js/Express    | PostgreSQL | 5434    |
| 13  | Chat Service         | 8013 | Node.js/Express    | -          | -       |
| 14  | Web BFF              | 8014 | Node.js/TypeScript | -          | -       |

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
