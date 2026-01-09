# AWS ECS with Fargate Infrastructure

> **Status:** 🔮 PLANNED (Phase 3)

This directory will contain AWS ECS Fargate deployment infrastructure for xshopai.

## When to Use ECS

Consider ECS over EKS when you need:

- Simpler container orchestration (no K8s complexity)
- Tight integration with AWS services
- Lower operational overhead
- Cost optimization for smaller workloads
- Serverless containers with Fargate

## Planned Structure

```
ecs/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/
│       ├── ecs-cluster/
│       ├── ecs-service/
│       ├── alb/
│       ├── rds/
│       ├── elasticache/
│       ├── documentdb/
│       ├── sns/
│       └── secrets-manager/
├── task-definitions/
│   └── *.json
└── environments/
    ├── dev.tfvars
    ├── staging.tfvars
    └── prod.tfvars
```

## Dapr on ECS

Dapr can run on ECS using the sidecar pattern:

- Dapr sidecar runs in same task definition
- Uses AWS SNS/SQS for pub/sub
- Uses ElastiCache (Redis) for state store
- Uses Secrets Manager for secrets

## AWS Services Mapping

| Azure Resource | AWS Equivalent |
|---------------|----------------|
| Container Apps | ECS Fargate |
| Service Bus | SNS + SQS |
| Redis Cache | ElastiCache |
| Cosmos DB | DocumentDB |
| PostgreSQL | RDS PostgreSQL |
| Key Vault | Secrets Manager |
| Container Registry | ECR |
| Log Analytics | CloudWatch Logs |

## Resources

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Dapr on AWS ECS](https://docs.dapr.io/operations/hosting/ecs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
