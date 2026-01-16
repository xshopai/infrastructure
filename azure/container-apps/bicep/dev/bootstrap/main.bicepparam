using './main.bicep'

param environment = 'dev'

// NOTE: location is overridden at deployment time via workflow input
// This default is only used for local testing/validation
param location = 'swedencentral'

param acrName = 'xshopaimodulesdev'
param acrSku = 'Basic'
param tags = {
  Environment: 'Development'
  ManagedBy: 'Bicep'
  Project: 'xshopai'
}
