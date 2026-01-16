// ========================================
// Development Environment Parameters
// ========================================
// Purpose: Parameter values for dev environment platform infrastructure
// Usage: az deployment sub create --location eastus --template-file main.bicep --parameters main.bicepparam
// ========================================

using './main.bicep'

// ========================================
// Environment Configuration
// ========================================

param location = 'eastus'
param environment = 'dev'

// ========================================
// Tags
// ========================================

param tags = {
  Environment: 'dev'
  Project: 'xshopai'
  ManagedBy: 'Bicep'
  CostCenter: 'Engineering'
  Owner: 'DevOps Team'
  Criticality: 'Low'
}

// ========================================
// Log Analytics
// ========================================

// Dev environment: 30 days retention (cost optimization)
param logAnalyticsRetentionDays = 30

// ========================================
// Deployment Notes
// ========================================
/*
To deploy this environment:

1. Validate template:
   az deployment sub validate \
     --location eastus \
     --template-file main.bicep \
     --parameters main.bicepparam

2. Deploy (What-If first):
   az deployment sub what-if \
     --location eastus \
     --template-file main.bicep \
     --parameters main.bicepparam

3. Deploy (actual):
   az deployment sub create \
     --name "xshopai-dev-$(date +%Y%m%d-%H%M%S)" \
     --location eastus \
     --template-file main.bicep \
     --parameters main.bicepparam

4. Get outputs:
   az deployment sub show \
     --name <deployment-name> \
     --query properties.outputs

Expected Resources Created:
- Resource Group: rg-xshopai-dev
- Log Analytics: log-xshopai-dev
- Container Apps Environment: cae-xshopai-dev
- Managed Identity: id-xshopai-dev
- Key Vault: kv-xshopai-dev

Estimated Monthly Cost (Dev): ~$50-100 USD
*/
