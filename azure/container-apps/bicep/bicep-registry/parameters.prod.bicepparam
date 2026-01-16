using './main.bicep'

param environment = 'prod'
param location = 'swedencentral'
param acrName = 'xshopaimodules'
param acrSku = 'Basic'
param tags = {
  Environment: 'Production'
  ManagedBy: 'Bicep'
  Project: 'xshopai'
}
