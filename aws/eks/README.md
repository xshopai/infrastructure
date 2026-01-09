# AWS Elastic Kubernetes Service (EKS) Infrastructure

> **Status:** 🔮 PLANNED (Phase 3)

This directory will contain AWS EKS deployment infrastructure for xshopai.

## When to Use EKS

Consider EKS when you need:

- Kubernetes on AWS
- Multi-cloud Kubernetes strategy
- Advanced K8s features and customization
- Service mesh support
- Complex networking requirements
- Existing Kubernetes expertise

## Planned Structure

```
eks/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/
│       ├── eks-cluster/
│       ├── node-groups/
│       ├── ecr/
│       ├── rds/
│       ├── elasticache/
│       ├── documentdb/
│       └── secrets-manager/
├── helm/
│   └── values/
│       ├── dev.yaml
│       ├── staging.yaml
│       └── prod.yaml
└── manifests/
    ├── namespaces/
    ├── dapr/
    └── services/
```

## Dapr on EKS

Dapr runs natively on Kubernetes:

```bash
# Install Dapr on EKS
dapr init -k

# Or via Helm
helm repo add dapr https://dapr.github.io/helm-charts/
helm install dapr dapr/dapr --namespace dapr-system
```

## Migration from AKS to EKS

Since both use Kubernetes, migration is straightforward:

1. Create EKS cluster via Terraform
2. Configure Dapr components (same CRDs)
3. Deploy services using same Helm charts/manifests
4. Update CI/CD to target EKS

## Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Dapr on Kubernetes](https://docs.dapr.io/operations/hosting/kubernetes/)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
