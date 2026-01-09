# Operations Runbook

This runbook provides procedures for common operational tasks and incident response for the xshopai platform on Azure Container Apps.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Deployment Procedures](#deployment-procedures)
3. [Scaling Operations](#scaling-operations)
4. [Troubleshooting](#troubleshooting)
5. [Incident Response](#incident-response)
6. [Backup and Recovery](#backup-and-recovery)
7. [Maintenance Tasks](#maintenance-tasks)

---

## Daily Operations

### Health Check Dashboard

```bash
# Check all Container Apps status
az containerapp list \
  --resource-group rg-xshopai-prod \
  --query "[].{Name:name, Status:properties.runningStatus, Replicas:properties.template.scale.minReplicas}" \
  -o table

# Check specific service health
curl -s https://ca-user-service.orangebeach-xxxxxxx.uksouth.azurecontainerapps.io/health | jq
```

### Log Review

```bash
# View recent logs for a service
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --type console \
  --tail 100

# View Dapr sidecar logs
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --type system \
  --tail 100
```

### Query Log Analytics

```kusto
// Errors in the last hour
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where Log_s contains "error" or Log_s contains "Error"
| project TimeGenerated, ContainerAppName_s, Log_s
| order by TimeGenerated desc

// Request latency by service
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(1h)
| where Log_s contains "request completed"
| parse Log_s with * "duration=" Duration:double "ms"
| summarize avg(Duration), percentile(Duration, 95), percentile(Duration, 99) by ContainerAppName_s
```

---

## Deployment Procedures

### Deploy Infrastructure Changes

```bash
# 1. Validate Bicep template
az bicep build --file azure/container-apps/bicep/main.bicep

# 2. Preview changes (what-if)
az deployment group what-if \
  --resource-group rg-xshopai-prod \
  --template-file azure/container-apps/bicep/main.bicep \
  --parameters azure/container-apps/bicep/parameters/prod.bicepparam

# 3. Deploy changes
az deployment group create \
  --resource-group rg-xshopai-prod \
  --template-file azure/container-apps/bicep/main.bicep \
  --parameters azure/container-apps/bicep/parameters/prod.bicepparam
```

### Deploy Service Update

```bash
# 1. Build and push new image
IMAGE="crxshopaiprod.azurecr.io/user-service:v1.2.0"
docker build -t $IMAGE ./user-service
docker push $IMAGE

# 2. Update Container App
az containerapp update \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --image $IMAGE
```

### Rollback Deployment

```bash
# 1. List revisions
az containerapp revision list \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  -o table

# 2. Activate previous revision
az containerapp revision activate \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --revision ca-user-service--xxxxx

# 3. Route traffic to previous revision
az containerapp ingress traffic set \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --revision-weight ca-user-service--xxxxx=100
```

---

## Scaling Operations

### Manual Scaling

```bash
# Scale up
az containerapp update \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --min-replicas 5 \
  --max-replicas 20

# Scale down
az containerapp update \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --min-replicas 2 \
  --max-replicas 10
```

### Check Current Scale

```bash
az containerapp replica list \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  -o table
```

### Database Scaling

```bash
# Scale PostgreSQL
az postgres flexible-server update \
  --name psql-xshopai-prod \
  --resource-group rg-xshopai-prod \
  --sku-name Standard_D4s_v3

# Scale Redis
az redis update \
  --name redis-xshopai-prod \
  --resource-group rg-xshopai-prod \
  --sku Standard \
  --vm-size c1
```

---

## Troubleshooting

### Service Not Starting

```bash
# 1. Check revision status
az containerapp revision show \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --revision <revision-name>

# 2. Check startup logs
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --type console \
  --tail 200

# 3. Check for resource constraints
az containerapp show \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --query "properties.template.containers[0].resources"
```

### Dapr Connection Issues

```bash
# 1. Verify Dapr component status
az containerapp env dapr-component list \
  --name cae-xshopai-prod \
  --resource-group rg-xshopai-prod \
  -o table

# 2. Check Dapr sidecar logs
az containerapp logs show \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --type system \
  --follow

# 3. Test Dapr endpoint from within container
az containerapp exec \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --command -- curl http://localhost:3500/v1.0/healthz
```

### Database Connection Issues

```bash
# Check Cosmos DB status
az cosmosdb show \
  --name cosmos-xshopai-prod \
  --resource-group rg-xshopai-prod \
  --query "failoverPolicies"

# Check PostgreSQL status
az postgres flexible-server show \
  --name psql-xshopai-prod \
  --resource-group rg-xshopai-prod \
  --query "state"

# Test PostgreSQL connection
az postgres flexible-server connect \
  --name psql-xshopai-prod \
  --admin-user <admin-user> \
  --admin-password <admin-password> \
  --database-name orders
```

### High Latency Investigation

```kusto
// Log Analytics query for slow requests
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where Log_s contains "duration"
| parse Log_s with * "duration=" Duration:double *
| where Duration > 1000
| project TimeGenerated, ContainerAppName_s, Log_s, Duration
| order by Duration desc
```

---

## Incident Response

### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| SEV-1 | Complete outage | 15 minutes | All services down |
| SEV-2 | Major degradation | 30 minutes | Critical service down |
| SEV-3 | Minor degradation | 2 hours | Non-critical service issues |
| SEV-4 | Low impact | 24 hours | Performance optimization |

### SEV-1: Complete Outage

1. **Assess** - Check Azure status page and Container Apps environment
2. **Communicate** - Notify stakeholders via incident channel
3. **Mitigate** - Attempt failover or rollback
4. **Resolve** - Fix root cause
5. **Post-mortem** - Document and prevent recurrence

```bash
# Quick health check of all services
for app in user-service auth-service cart-service order-service; do
  echo "Checking ca-$app..."
  az containerapp show \
    --name "ca-$app" \
    --resource-group rg-xshopai-prod \
    --query "properties.runningStatus" -o tsv
done

# Check Container Apps Environment
az containerapp env show \
  --name cae-xshopai-prod \
  --resource-group rg-xshopai-prod \
  --query "properties.provisioningState"
```

### SEV-2: Service Down

```bash
# 1. Identify failed service
az containerapp revision list \
  --name ca-order-service \
  --resource-group rg-xshopai-prod \
  --query "[?properties.runningStatus!='Running']"

# 2. Check recent changes
az containerapp revision list \
  --name ca-order-service \
  --resource-group rg-xshopai-prod \
  -o table

# 3. Rollback if needed
az containerapp revision activate \
  --name ca-order-service \
  --resource-group rg-xshopai-prod \
  --revision <previous-revision>
```

---

## Backup and Recovery

### Database Backups

**Cosmos DB:**
- Automatic continuous backups (point-in-time restore)
- 30-day retention

```bash
# Restore to point in time
az cosmosdb restore \
  --target-database-account-name cosmos-xshopai-restore \
  --account-name cosmos-xshopai-prod \
  --resource-group rg-xshopai-prod \
  --restore-timestamp "2024-01-15T10:00:00Z"
```

**PostgreSQL:**
- Automatic daily backups
- 35-day retention

```bash
# Point-in-time restore
az postgres flexible-server restore \
  --resource-group rg-xshopai-prod \
  --name psql-xshopai-restore \
  --source-server psql-xshopai-prod \
  --restore-time "2024-01-15T10:00:00Z"
```

### Key Vault Backup

```bash
# Backup all secrets
az keyvault secret list \
  --vault-name kv-xshopai-prod \
  --query "[].name" -o tsv | while read secret; do
  az keyvault secret backup \
    --vault-name kv-xshopai-prod \
    --name $secret \
    --file "backup-$secret.blob"
done
```

---

## Maintenance Tasks

### Certificate Renewal

Container Apps handles TLS certificates automatically. For custom domains:

```bash
# Add custom certificate
az containerapp ssl upload \
  --name ca-web-bff \
  --resource-group rg-xshopai-prod \
  --hostname www.xshopai.com \
  --certificate-file cert.pfx \
  --certificate-password <password>
```

### Secret Rotation

```bash
# 1. Generate new secret
NEW_SECRET=$(openssl rand -base64 32)

# 2. Update Key Vault
az keyvault secret set \
  --vault-name kv-xshopai-prod \
  --name JWT-SECRET \
  --value "$NEW_SECRET"

# 3. Restart services to pick up new secret
az containerapp revision restart \
  --name ca-auth-service \
  --resource-group rg-xshopai-prod \
  --revision <current-revision>
```

### Cleanup Old Revisions

```bash
# List all revisions
az containerapp revision list \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  -o table

# Deactivate old revisions (keep last 5)
az containerapp revision list \
  --name ca-user-service \
  --resource-group rg-xshopai-prod \
  --query "sort_by([?properties.active], &properties.createdTime)[:-5].name" -o tsv | \
while read rev; do
  az containerapp revision deactivate \
    --name ca-user-service \
    --resource-group rg-xshopai-prod \
    --revision $rev
done
```

### Resource Cleanup (Dev/Staging)

```bash
# Delete old Container App revisions
az containerapp revision list \
  --name ca-user-service \
  --resource-group rg-xshopai-dev \
  --query "[?properties.active==\`false\`].name" -o tsv | \
while read rev; do
  echo "Deactivating $rev"
  az containerapp revision deactivate \
    --name ca-user-service \
    --resource-group rg-xshopai-dev \
    --revision $rev
done

# Clean up ACR images (keep last 10 tags per image)
az acr repository show-tags \
  --name crxshopaidev \
  --repository user-service \
  --orderby time_desc \
  --query "[10:]" -o tsv | \
while read tag; do
  az acr repository delete \
    --name crxshopaidev \
    --image user-service:$tag \
    --yes
done
```

---

## Contacts

| Role | Contact | Escalation |
|------|---------|------------|
| On-call Engineer | PagerDuty | After 15 min |
| Platform Lead | @platform-lead | SEV-1/SEV-2 |
| Security | @security-team | Security incidents |
| Azure Support | Premier Support | Infrastructure issues |
