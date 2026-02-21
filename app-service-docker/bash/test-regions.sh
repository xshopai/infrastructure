#!/bin/bash
# Tests B1 App Service Plan availability + checks supporting service availability per region.
# Run from the bash/ directory after az login.

RG="rg-xshopai-dev-1c0f"
SUBID=$(az account show --query id -o tsv 2>/dev/null)

REGIONS=(
  northeurope westeurope uksouth francecentral germanywestcentral
  norwayeast swedencentral eastus eastus2 centralus
  westus2 southcentralus canadacentral australiaeast southeastasia japaneast
)

echo ""
echo "============================================================"
echo " B1 App Service Plan Availability Test"
echo " Subscription: $SUBID"
echo " Resource Group: $RG"
echo "============================================================"
echo ""

OK_REGIONS=()
QUOTA_REGIONS=()
CAPACITY_REGIONS=()

for region in "${REGIONS[@]}"; do
  plan="tst-$(echo "$region" | tr -d '-' | cut -c1-10)-b1"
  printf "  Testing %-22s ... " "$region"

  result=$(az appservice plan create \
    --name "$plan" \
    --resource-group "$RG" \
    --location "$region" \
    --sku B1 \
    --is-linux \
    --output none 2>&1)

  if echo "$result" | grep -qi "Current Limit.*: 0\|quota"; then
    echo "❌  QUOTA=0 (subscription has no B1 entitlement here)"
    QUOTA_REGIONS+=("$region")
  elif echo "$result" | grep -qi "no available instances\|increase capacity\|retry your request"; then
    echo "⚠️   NO CAPACITY (quota exists, but no free instances right now)"
    CAPACITY_REGIONS+=("$region")
  elif echo "$result" | grep -qi "error\|Error"; then
    err=$(echo "$result" | grep -i "error\|ERROR" | head -1 | sed 's/.*ERROR: //' | cut -c1-80)
    echo "✗   ERROR: $err"
  else
    az appservice plan delete \
      --name "$plan" \
      --resource-group "$RG" \
      --yes --output none 2>/dev/null &
    echo "✅  OK"
    OK_REGIONS+=("$region")
  fi
done

wait  # clean up background deletes

echo ""
echo "============================================================"
echo " RESULTS SUMMARY"
echo "============================================================"
echo ""
if [ ${#OK_REGIONS[@]} -gt 0 ]; then
  echo "✅  AVAILABLE (quota + capacity confirmed):"
  for r in "${OK_REGIONS[@]}"; do echo "     $r"; done
else
  echo "✅  AVAILABLE: none found"
fi
echo ""
if [ ${#CAPACITY_REGIONS[@]} -gt 0 ]; then
  echo "⚠️   QUOTA OK but NO CAPACITY right now (may free up later):"
  for r in "${CAPACITY_REGIONS[@]}"; do echo "     $r"; done
fi
echo ""
if [ ${#QUOTA_REGIONS[@]} -gt 0 ]; then
  echo "❌  QUOTA=0 (subscription limit — needs support request to increase):"
  for r in "${QUOTA_REGIONS[@]}"; do echo "     $r"; done
fi

echo ""
echo "NOTE: 'QUOTA=0' requires raising a support ticket at:"
echo "  https://portal.azure.com/#view/Microsoft_Azure_Support/NewSupportRequestV3Blade"
echo "  Category: Service and subscription limits (quotas)"
echo "  Quota type: App Service -> Basic Instances"
echo ""
