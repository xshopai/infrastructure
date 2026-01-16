using './main.bicep'

param environment = 'dev'
param location = 'swedencentral'
param acrName = 'xshopaimodulesdev'
param acrSku = 'Basic'
param tags = {
  Environment: 'Development'
  ManagedBy: 'Bicep'
  Project: 'xshopai'
}
