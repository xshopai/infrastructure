using './main.bicep'

param environment = 'dev'
param location = 'swedencentral'
param acrName = 'xshopaimodules'
param acrSku = 'Basic'
param tags = {
  Environment: 'Development'
  ManagedBy: 'Bicep'
  Project: 'xshopai'
}
