# Azure Kubernetes Service (AKS) Infrastructure

> **Status:** 🔮 PLANNED (Phase 2)

This directory will contain AKS-based deployment infrastructure for xshopai.

## When to Use AKS

Consider AKS over Container Apps when you need:

- Fine-grained Kubernetes control
- Custom node pools with specific VM sizes
- GPU workloads
- Advanced networking (custom CNI, network policies)
- Multi-region active-active deployments
- Service mesh integration (Istio, Linkerd)
- More than 30 microservices
- Complex scheduling requirements

## Planned Structure

```
aks/
├── bicep/
│   ├── main.bicep
│   └── modules/
│       ├── aks-cluster.bicep
│       ├── node-pools.bicep
│       ├── container-registry.bicep
│       └── ...
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

## Migration Path

When migrating from Container Apps to AKS:

1. Infrastructure is created via Bicep (same pattern)
2. Dapr components become Kubernetes CRDs
3. Services deploy via Helm charts or K8s manifests
4. CI/CD workflows updated to use kubectl/helm

## Resources

- [Azure AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Dapr on Kubernetes](https://docs.dapr.io/operations/hosting/kubernetes/)
- [Azure AKS Best Practices](https://docs.microsoft.com/azure/aks/best-practices)
