#!/bin/bash
#==============================================================================
# Temporary fix: Update services until Bicep workflow redeploys
#==============================================================================

RG="rg-xshopai-development"

echo "Fixing Python and UI services..."

# Python services - clear startup commands
for service in product-service inventory-service; do
  echo "Updating $service..."
  APP="app-${service}-xshopai-development"
  
  # Method 1: Update via JSON patch
  MSYS_NO_PATHCONV=1 az rest \
    --method PATCH \
    --uri "https://management.azure.com/subscriptions/15253617-0c00-4b3b-9e13-f2390fccfd58/resourceGroups/${RG}/providers/Microsoft.Web/sites/${APP}/config/web?api-version=2022-09-01" \
    --body '{
      "properties": {
        "appCommandLine": ""
      }
    }'
  
  # Enable Oryx build  
  az webapp config appsettings set \
    --name "$APP" \
    --resource-group "$RG" \
    --settings \
      SCM_DO_BUILD_DURING_DEPLOYMENT=true \
      ENABLE_ORYX_BUILD=true \
    --output none
    
  echo "  ✓ $service updated"
done

# UI services - enable Oryx build
for service in admin-ui customer-ui; do
  echo "Updating $service..."
  APP="app-${service}-xshopai-development"
  
  # Clear startup command
  MSYS_NO_PATHCONV=1 az rest \
    --method PATCH \
    --uri "https://management.azure.com/subscriptions/15253617-0c00-4b3b-9e13-f2390fccfd58/resourceGroups/${RG}/providers/Microsoft.Web/sites/${APP}/config/web?api-version=2022-09-01" \
    --body '{
      "properties": {
        "appCommandLine": ""
      }
    }'
  
  # Enable Oryx build
  az webapp config appsettings set \
    --name "$APP" \
    --resource-group "$RG" \
    --settings \
      SCM_DO_BUILD_DURING_DEPLOYMENT=true \
      ENABLE_ORYX_BUILD=true \
    --output none
    
  echo "  ✓ $service updated"
done

echo ""
echo "✅ All services updated. Restarting to apply changes..."

# Restart all 4 services
for service in product-service inventory-service admin-ui customer-ui; do
  APP="app-${service}-xshopai-development"
  az webapp restart --name "$APP" --resource-group "$RG" --output none &
done

wait
echo "✅ All services restarted"
echo ""
echo "Services should now show default Azure App Service page until code is deployed."
