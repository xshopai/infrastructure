# =============================================================================
# xshopai Infrastructure Deployment Script for Azure Container Apps
# =============================================================================
# This script deploys all shared infrastructure resources required by the
# xshopai microservices platform on Azure Container Apps.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Sufficient permissions to create resources in the subscription
#
# Usage:
#   .\deploy-infra.ps1 [-Environment <env>] [-Subscription <sub>] [-Location <loc>] [-Suffix <sfx>]
#   
#   Environment:  dev (default), staging, or prod
#   Subscription: Azure subscription ID or name (will prompt if not provided)
#   Location:     Azure region (will prompt if not provided)
#   Suffix:       Unique suffix for globally-scoped resources (will prompt if not provided)
#
# Example:
#   .\deploy-infra.ps1
#   .\deploy-infra.ps1 -Environment dev -Location eastus
#   .\deploy-infra.ps1 -Environment dev -Location eastus -Suffix abc1
#   .\deploy-infra.ps1 -Environment prod -Subscription "My Subscription" -Location westus2 -Suffix prod01
# =============================================================================

param(
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    
    [string]$Subscription = "",
    
    [string]$Location = "",
    
    [string]$Suffix = ""
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$ProjectName = "xshopai"

# -----------------------------------------------------------------------------
# Get Azure Subscription
# -----------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($Subscription)) {
    Write-Host ""
    Write-Host "Available Azure Subscriptions:" -ForegroundColor Cyan
    Write-Host "-----------------------------------"
    az account list --query "[].{Name:name, ID:id, Default:isDefault}" -o table
    Write-Host ""
    $Subscription = Read-Host "Enter Subscription ID or Name"
    
    if ([string]::IsNullOrEmpty($Subscription)) {
        Write-Host "Subscription is required." -ForegroundColor Red
        exit 1
    }
}

# Set the subscription
Write-Host ""
Write-Host "Setting Azure subscription..." -ForegroundColor Yellow
az account set --subscription $Subscription
$SubscriptionId = az account show --query id -o tsv
$SubscriptionName = az account show --query name -o tsv
Write-Host "   Using subscription: $SubscriptionName ($SubscriptionId)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Get Azure Location
# -----------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($Location)) {
    Write-Host ""
    Write-Host "Common Azure Locations:" -ForegroundColor Cyan
    Write-Host "-----------------------------------"
    Write-Host "   eastus        - East US (Virginia)"
    Write-Host "   eastus2       - East US 2 (Virginia)"
    Write-Host "   westus        - West US (California)"
    Write-Host "   westus2       - West US 2 (Washington)"
    Write-Host "   westus3       - West US 3 (Arizona)"
    Write-Host "   centralus     - Central US (Iowa)"
    Write-Host "   northeurope   - North Europe (Ireland)"
    Write-Host "   westeurope    - West Europe (Netherlands)"
    Write-Host "   uksouth       - UK South (London)"
    Write-Host "   southeastasia - Southeast Asia (Singapore)"
    Write-Host "   australiaeast - Australia East (Sydney)"
    Write-Host ""
    $Location = Read-Host "Enter Azure Location [eastus]"
    if ([string]::IsNullOrEmpty($Location)) {
        $Location = "eastus"
    }
}

# Validate location
$ValidLocation = az account list-locations --query "[?name=='$Location'].name" -o tsv
if ([string]::IsNullOrEmpty($ValidLocation)) {
    Write-Host "Invalid location: $Location" -ForegroundColor Red
    Write-Host "   Run 'az account list-locations -o table' to see all valid locations."
    exit 1
}

Write-Host "   Using location: $Location" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Get Unique Suffix (for globally-scoped resources)
# -----------------------------------------------------------------------------
# Some Azure resources (ACR, Key Vault, Cosmos DB, Storage, Service Bus) have
# globally unique names. A suffix ensures uniqueness and avoids conflicts when
# resources are deleted and recreated.
# -----------------------------------------------------------------------------
$RandomBytes = New-Object byte[] 2
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($RandomBytes)
$DefaultSuffix = [BitConverter]::ToString($RandomBytes).Replace("-", "").ToLower()

if ([string]::IsNullOrEmpty($Suffix)) {
    Write-Host ""
    Write-Host "Unique Suffix for Globally-Scoped Resources:" -ForegroundColor Cyan
    Write-Host "-----------------------------------"
    Write-Host "   Some Azure resources require globally unique names."
    Write-Host "   A suffix helps avoid naming conflicts, especially after deletions."
    Write-Host "   Examples: abc1, dev01, team1, jd01"
    Write-Host ""
    $Suffix = Read-Host "Enter unique suffix (3-6 alphanumeric) [$DefaultSuffix]"
    if ([string]::IsNullOrEmpty($Suffix)) {
        $Suffix = $DefaultSuffix
    }
}

# Validate suffix (alphanumeric, 3-6 characters)
if ($Suffix -notmatch "^[a-z0-9]{3,6}$") {
    Write-Host "Invalid suffix: $Suffix" -ForegroundColor Red
    Write-Host "   Suffix must be 3-6 lowercase alphanumeric characters."
    exit 1
}

Write-Host "   Using suffix: $Suffix" -ForegroundColor Green

Write-Host "=============================================="
Write-Host "xshopai Infrastructure Deployment"
Write-Host "=============================================="
Write-Host "Environment:   $Environment"
Write-Host "Subscription:  $SubscriptionName"
Write-Host "Location:      $Location"
Write-Host "Suffix:        $Suffix"
Write-Host "=============================================="

# -----------------------------------------------------------------------------
# Resource Naming (following Azure naming conventions)
# -----------------------------------------------------------------------------
# Regional resources (unique within subscription): No suffix needed
# Global resources (unique across Azure): Suffix added for uniqueness
# -----------------------------------------------------------------------------

# Regional resources (no suffix needed)
$ResourceGroup = "rg-$ProjectName-$Environment"
$LogAnalytics = "law-$ProjectName-$Environment"
$ContainerEnv = "cae-$ProjectName-$Environment"
$RedisName = "redis-$ProjectName-$Environment"
$MySqlServer = "mysql-$ProjectName-$Environment"
$ManagedIdentity = "id-$ProjectName-$Environment"

# Global resources (suffix added for uniqueness)
$AcrName = "$ProjectName$Environment$Suffix"                      # No hyphens allowed
$ServiceBus = "sb-$ProjectName-$Environment-$Suffix"
$CosmosAccount = "cosmos-$ProjectName-$Environment-$Suffix"
$KeyVault = "kv-$ProjectName-$Environment-$Suffix"
$StorageAccount = "st$ProjectName$Environment$Suffix"             # No hyphens allowed

Write-Host ""
Write-Host "Resources to be created:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Regional Resources (subscription-scoped):"
Write-Host "   -----------------------------------------"
Write-Host "   Resource Group:      $ResourceGroup"
Write-Host "   Log Analytics:       $LogAnalytics"
Write-Host "   Container Apps Env:  $ContainerEnv"
Write-Host "   Redis Cache:         $RedisName"
Write-Host "   MySQL Server:        $MySqlServer"
Write-Host "   Managed Identity:    $ManagedIdentity"
Write-Host ""
Write-Host "   Global Resources (suffix: $Suffix):" -ForegroundColor Yellow
Write-Host "   -----------------------------------------"
Write-Host "   Container Registry:  $AcrName"
Write-Host "   Service Bus:         $ServiceBus"
Write-Host "   Cosmos DB:           $CosmosAccount"
Write-Host "   Key Vault:           $KeyVault"
Write-Host "   Storage Account:     $StorageAccount"
Write-Host ""

# Confirm before proceeding
$Confirm = Read-Host "Do you want to proceed? (y/N)"
if ($Confirm -ne "y" -and $Confirm -ne "Y") {
    Write-Host "Deployment cancelled." -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# 1. Create Resource Group
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Resource Group..." -ForegroundColor Yellow
az group create `
    --name $ResourceGroup `
    --location $Location `
    --tags "project=$ProjectName" "environment=$Environment" "suffix=$Suffix" `
    --output none

Write-Host "   Resource Group: $ResourceGroup" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. Create User-Assigned Managed Identity
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Managed Identity..." -ForegroundColor Yellow
az identity create `
    --name $ManagedIdentity `
    --resource-group $ResourceGroup `
    --location $Location `
    --output none

$IdentityId = az identity show `
    --name $ManagedIdentity `
    --resource-group $ResourceGroup `
    --query id -o tsv

$IdentityClientId = az identity show `
    --name $ManagedIdentity `
    --resource-group $ResourceGroup `
    --query clientId -o tsv

$IdentityPrincipalId = az identity show `
    --name $ManagedIdentity `
    --resource-group $ResourceGroup `
    --query principalId -o tsv

Write-Host "   Managed Identity: $ManagedIdentity" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Create Azure Container Registry
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Azure Container Registry..." -ForegroundColor Yellow
az acr create `
    --name $AcrName `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Basic `
    --admin-enabled true `
    --output none

$AcrLoginServer = az acr show `
    --name $AcrName `
    --resource-group $ResourceGroup `
    --query loginServer -o tsv

# Grant managed identity access to ACR
$SubscriptionId = az account show --query id -o tsv
az role assignment create `
    --assignee $IdentityPrincipalId `
    --role "AcrPull" `
    --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerRegistry/registries/$AcrName" `
    --output none 2>$null

Write-Host "   Container Registry: $AcrLoginServer" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Create Log Analytics Workspace
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Log Analytics Workspace..." -ForegroundColor Yellow
az monitor log-analytics workspace create `
    --workspace-name $LogAnalytics `
    --resource-group $ResourceGroup `
    --location $Location `
    --output none

$LogAnalyticsId = az monitor log-analytics workspace show `
    --workspace-name $LogAnalytics `
    --resource-group $ResourceGroup `
    --query customerId -o tsv

$LogAnalyticsKey = az monitor log-analytics workspace get-shared-keys `
    --workspace-name $LogAnalytics `
    --resource-group $ResourceGroup `
    --query primarySharedKey -o tsv

Write-Host "   Log Analytics: $LogAnalytics" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Create Container Apps Environment
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Container Apps Environment..." -ForegroundColor Yellow
az containerapp env create `
    --name $ContainerEnv `
    --resource-group $ResourceGroup `
    --location $Location `
    --logs-workspace-id $LogAnalyticsId `
    --logs-workspace-key $LogAnalyticsKey `
    --output none

Write-Host "   Container Apps Environment: $ContainerEnv" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. Create Azure Service Bus Namespace
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Service Bus Namespace..." -ForegroundColor Yellow
az servicebus namespace create `
    --name $ServiceBus `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard `
    --output none

$ServiceBusConnection = az servicebus namespace authorization-rule keys list `
    --namespace-name $ServiceBus `
    --resource-group $ResourceGroup `
    --name RootManageSharedAccessKey `
    --query primaryConnectionString -o tsv

# Configure Service Bus network rules - allow Azure services
az servicebus namespace network-rule-set update `
    --namespace-name $ServiceBus `
    --resource-group $ResourceGroup `
    --default-action Allow `
    --enable-trusted-service-access true `
    --output none 2>$null

Write-Host "   Service Bus: $ServiceBus (Azure services allowed)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. Create Azure Cache for Redis
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Azure Cache for Redis..." -ForegroundColor Yellow
Write-Host "   (This may take 10-15 minutes...)" -ForegroundColor Gray
az redis create `
    --name $RedisName `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Basic `
    --vm-size c0 `
    --output none

# Wait for Redis to be ready
Write-Host "   Waiting for Redis to be provisioned..."
az redis wait `
    --name $RedisName `
    --resource-group $ResourceGroup `
    --created

$RedisHost = az redis show `
    --name $RedisName `
    --resource-group $ResourceGroup `
    --query hostName -o tsv

$RedisKey = az redis list-keys `
    --name $RedisName `
    --resource-group $ResourceGroup `
    --query primaryKey -o tsv

$RedisPort = "6380"

# Note: Azure Cache for Redis Basic/Standard tiers don't support VNet/firewall rules
# For production, consider Premium tier with VNet integration
# Redis is secured via access key authentication and TLS

Write-Host "   Redis Cache: $RedisHost (secured via access key + TLS)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 8. Create Azure Cosmos DB (MongoDB API)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Cosmos DB (MongoDB API)..." -ForegroundColor Yellow
az cosmosdb create `
    --name $CosmosAccount `
    --resource-group $ResourceGroup `
    --kind MongoDB `
    --server-version "4.2" `
    --default-consistency-level Session `
    --locations regionName=$Location failoverPriority=0 isZoneRedundant=false `
    --output none

# Configure Cosmos DB firewall - allow Azure services and portal access
Write-Host "   Configuring Cosmos DB firewall rules..." -ForegroundColor Gray
az cosmosdb update `
    --name $CosmosAccount `
    --resource-group $ResourceGroup `
    --enable-public-network true `
    --enable-analytical-storage false `
    --output none 2>$null

# Allow access from Azure services (including Container Apps)
az cosmosdb update `
    --name $CosmosAccount `
    --resource-group $ResourceGroup `
    --ip-range-filter "0.0.0.0" `
    --output none 2>$null

$CosmosConnection = az cosmosdb keys list `
    --name $CosmosAccount `
    --resource-group $ResourceGroup `
    --type connection-strings `
    --query "connectionStrings[0].connectionString" -o tsv

# Create databases for services
Write-Host "   Creating databases..."
$Databases = @("user-db", "product-db", "order-db", "cart-db", "review-db", "inventory-db", "audit-db")
foreach ($DbName in $Databases) {
    az cosmosdb mongodb database create `
        --account-name $CosmosAccount `
        --resource-group $ResourceGroup `
        --name $DbName `
        --output none 2>$null
}

Write-Host "   Cosmos DB: $CosmosAccount" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 9. Create Azure Database for MySQL (Flexible Server)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating MySQL Flexible Server..." -ForegroundColor Yellow

# Generate a random password for MySQL
$MySqlAdminUser = "xshopaiadmin"
$RandomBytes = New-Object byte[] 12
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($RandomBytes)
$RandomString = [Convert]::ToBase64String($RandomBytes) -replace '[^a-zA-Z0-9]', ''
$MySqlAdminPassword = "XShop$($RandomString.Substring(0,12))!"

az mysql flexible-server create `
    --name $MySqlServer `
    --resource-group $ResourceGroup `
    --location $Location `
    --admin-user $MySqlAdminUser `
    --admin-password $MySqlAdminPassword `
    --sku-name Standard_B1ms `
    --tier Burstable `
    --storage-size 32 `
    --version "8.0.21" `
    --public-access 0.0.0.0 `
    --output none

$MySqlHost = az mysql flexible-server show `
    --name $MySqlServer `
    --resource-group $ResourceGroup `
    --query fullyQualifiedDomainName -o tsv

# Configure MySQL firewall rules
Write-Host "   Configuring MySQL firewall rules..." -ForegroundColor Gray

# Allow all Azure services (required for Container Apps)
az mysql flexible-server firewall-rule create `
    --resource-group $ResourceGroup `
    --name $MySqlServer `
    --rule-name "AllowAllAzureServices" `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0 `
    --output none 2>$null

# For production, you would add specific IP ranges instead:
# az mysql flexible-server firewall-rule create `
#     --resource-group $ResourceGroup `
#     --name $MySqlServer `
#     --rule-name "ContainerAppsOutbound" `
#     --start-ip-address <CAE_OUTBOUND_IP_START> `
#     --end-ip-address <CAE_OUTBOUND_IP_END>

# Create databases
Write-Host "   Creating databases..."
$MySqlDatabases = @("order_db", "payment_db")
foreach ($DbName in $MySqlDatabases) {
    az mysql flexible-server db create `
        --resource-group $ResourceGroup `
        --server-name $MySqlServer `
        --database-name $DbName `
        --output none 2>$null
}

Write-Host "   MySQL Server: $MySqlHost" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 10. Create Azure Key Vault
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Key Vault..." -ForegroundColor Yellow
az keyvault create `
    --name $KeyVault `
    --resource-group $ResourceGroup `
    --location $Location `
    --enable-rbac-authorization true `
    --output none

# Configure Key Vault network rules - allow Azure services
Write-Host "   Configuring Key Vault network access..." -ForegroundColor Gray
az keyvault update `
    --name $KeyVault `
    --resource-group $ResourceGroup `
    --default-action Allow `
    --bypass AzureServices `
    --output none 2>$null

# Grant managed identity access to Key Vault
az role assignment create `
    --assignee $IdentityPrincipalId `
    --role "Key Vault Secrets User" `
    --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVault" `
    --output none 2>$null

$KeyVaultUrl = "https://$KeyVault.vault.azure.net/"

Write-Host "   Key Vault: $KeyVaultUrl" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 11. Store Secrets in Key Vault
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Storing secrets in Key Vault..." -ForegroundColor Yellow

try {
    $CurrentUserId = az ad signed-in-user show --query id -o tsv 2>$null
    
    if ($CurrentUserId) {
        # Grant current user access to set secrets
        az role assignment create `
            --assignee $CurrentUserId `
            --role "Key Vault Secrets Officer" `
            --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVault" `
            --output none 2>$null
        
        # Wait for role assignment to propagate
        Start-Sleep -Seconds 30

        # Store secrets
        az keyvault secret set --vault-name $KeyVault --name "service-bus-connection" --value $ServiceBusConnection --output none 2>$null
        az keyvault secret set --vault-name $KeyVault --name "redis-password" --value $RedisKey --output none 2>$null
        az keyvault secret set --vault-name $KeyVault --name "cosmos-connection" --value $CosmosConnection --output none 2>$null
        az keyvault secret set --vault-name $KeyVault --name "mysql-password" --value $MySqlAdminPassword --output none 2>$null
        az keyvault secret set --vault-name $KeyVault --name "mysql-connection" --value "Server=$MySqlHost;Database=order_db;User=$MySqlAdminUser;Password=$MySqlAdminPassword;SslMode=Required" --output none 2>$null
        
        Write-Host "   Secrets stored in Key Vault" -ForegroundColor Green
    }
}
catch {
    Write-Host "   Could not store secrets (run 'az login' with user account)" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 12. Create Storage Account (for Dapr state store fallback)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating Storage Account..." -ForegroundColor Yellow
az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --allow-blob-public-access false `
    --min-tls-version TLS1_2 `
    --output none

# Configure Storage Account network rules - allow Azure services
Write-Host "   Configuring Storage Account network access..." -ForegroundColor Gray
az storage account update `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --default-action Allow `
    --bypass AzureServices Logging Metrics `
    --output none 2>$null

$StorageKey = az storage account keys list `
    --account-name $StorageAccount `
    --resource-group $ResourceGroup `
    --query "[0].value" -o tsv

Write-Host "   Storage Account: $StorageAccount (Azure services allowed, TLS 1.2)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 13. Configure Dapr Components
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Configuring Dapr Components..." -ForegroundColor Yellow

# Dapr Pub/Sub Component (Service Bus)
$PubSubYaml = @"
componentType: pubsub.azure.servicebus.queues
version: v1
metadata:
  - name: connectionString
    value: "$ServiceBusConnection"
  - name: consumerID
    value: "xshopai-consumer"
scopes:
  - user-service
  - auth-service
  - product-service
  - order-service
  - cart-service
  - inventory-service
  - payment-service
  - notification-service
  - audit-service
  - review-service
  - order-processor-service
"@

$PubSubYaml | az containerapp env dapr-component set `
    --name $ContainerEnv `
    --resource-group $ResourceGroup `
    --dapr-component-name "pubsub" `
    --yaml -

Write-Host "   Dapr pubsub component configured" -ForegroundColor Green

# Dapr State Store Component (Redis)
$StateStoreYaml = @"
componentType: state.redis
version: v1
metadata:
  - name: redisHost
    value: "${RedisHost}:${RedisPort}"
  - name: redisPassword
    value: "$RedisKey"
  - name: enableTLS
    value: "true"
scopes:
  - cart-service
  - order-service
  - user-service
  - auth-service
"@

$StateStoreYaml | az containerapp env dapr-component set `
    --name $ContainerEnv `
    --resource-group $ResourceGroup `
    --dapr-component-name "statestore" `
    --yaml -

Write-Host "   Dapr statestore component configured" -ForegroundColor Green

# Dapr Secret Store Component (Key Vault)
$SecretStoreYaml = @"
componentType: secretstores.azure.keyvault
version: v1
metadata:
  - name: vaultName
    value: "$KeyVault"
  - name: azureClientId
    value: "$IdentityClientId"
"@

$SecretStoreYaml | az containerapp env dapr-component set `
    --name $ContainerEnv `
    --resource-group $ResourceGroup `
    --dapr-component-name "secretstore" `
    --yaml -

Write-Host "   Dapr secretstore component configured" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "Infrastructure Deployment Complete!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Deployment Configuration:" -ForegroundColor Cyan
Write-Host "   Environment:            $Environment"
Write-Host "   Location:               $Location"
Write-Host "   Suffix:                 $Suffix"
Write-Host ""
Write-Host "Resource Summary:" -ForegroundColor Cyan
Write-Host "   Resource Group:         $ResourceGroup"
Write-Host "   Container Registry:     $AcrLoginServer"
Write-Host "   Container Apps Env:     $ContainerEnv"
Write-Host "   Service Bus:            $ServiceBus.servicebus.windows.net"
Write-Host "   Redis Cache:            $RedisHost"
Write-Host "   Cosmos DB:              $CosmosAccount.mongo.cosmos.azure.com"
Write-Host "   MySQL Server:           $MySqlHost"
Write-Host "   Key Vault:              $KeyVaultUrl"
Write-Host "   Managed Identity:       $ManagedIdentity"
Write-Host "   Storage Account:        $StorageAccount"
Write-Host ""
Write-Host "Credentials (save securely!):" -ForegroundColor Yellow
Write-Host "   MySQL Admin User:       $MySqlAdminUser"
Write-Host "   MySQL Admin Password:   $MySqlAdminPassword"
Write-Host ""
Write-Host "Environment Variables for Services:" -ForegroundColor Cyan
Write-Host "   `$env:RESOURCE_GROUP=`"$ResourceGroup`""
Write-Host "   `$env:ACR_NAME=`"$AcrName`""
Write-Host "   `$env:ACR_LOGIN_SERVER=`"$AcrLoginServer`""
Write-Host "   `$env:CONTAINER_ENV=`"$ContainerEnv`""
Write-Host "   `$env:MANAGED_IDENTITY_ID=`"$IdentityId`""
Write-Host "   `$env:SUFFIX=`"$Suffix`""
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Save the suffix '$Suffix' - you'll need it for service deployments"
Write-Host "   2. Deploy individual services using their scripts\aca.ps1"
Write-Host "   3. Configure DNS and custom domains"
Write-Host "   4. Set up monitoring and alerts"
Write-Host ""
Write-Host "To deploy a service:" -ForegroundColor Cyan
Write-Host "   cd ..\..\..\<service-name>\scripts"
Write-Host "   .\aca.ps1 -Environment $Environment"
Write-Host ""
Write-Host "Important: The suffix '$Suffix' is stored as a tag on the resource group." -ForegroundColor Yellow
Write-Host "   To retrieve it later: az group show -n $ResourceGroup --query `"tags.suffix`" -o tsv"
Write-Host ""
