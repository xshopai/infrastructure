#!/bin/bash
# Checks whether all xshopai required services are available in candidate regions.
# Uses Azure provider APIs with proper display-name matching.

SUBID=$(az account show --query id -o tsv 2>/dev/null)
CANDIDATES=(francecentral norwayeast swedencentral centralus westus2 canadacentral australiaeast southeastasia)

# Map from slug to searchable display-name fragment
declare -A DISPLAY
DISPLAY[francecentral]="France Central"
DISPLAY[norwayeast]="Norway East"
DISPLAY[swedencentral]="Sweden Central"
DISPLAY[centralus]="Central US"
DISPLAY[westus2]="West US 2"
DISPLAY[canadacentral]="Canada Central"
DISPLAY[australiaeast]="Australia East"
DISPLAY[southeastasia]="Southeast Asia"

echo "Fetching provider availability data..."

# Grab location lists for each required provider/type once
COSMOS_LOCS=$(az provider show --namespace Microsoft.DocumentDB \
  --query "resourceTypes[?resourceType=='databaseAccounts'].locations[]" -o tsv 2>/dev/null)
PSQL_LOCS=$(az provider show --namespace Microsoft.DBforPostgreSQL \
  --query "resourceTypes[?resourceType=='flexibleServers'].locations[]" -o tsv 2>/dev/null)
MYSQL_LOCS=$(az provider show --namespace Microsoft.DBforMySQL \
  --query "resourceTypes[?resourceType=='flexibleServers'].locations[]" -o tsv 2>/dev/null)
REDIS_LOCS=$(az provider show --namespace Microsoft.Cache \
  --query "resourceTypes[?resourceType=='redis'].locations[]" -o tsv 2>/dev/null)
SQL_LOCS=$(az provider show --namespace Microsoft.Sql \
  --query "resourceTypes[?resourceType=='servers'].locations[]" -o tsv 2>/dev/null)
ACI_LOCS=$(az provider show --namespace Microsoft.ContainerInstance \
  --query "resourceTypes[?resourceType=='containerGroups'].locations[]" -o tsv 2>/dev/null)

echo ""
printf "%-20s %-10s %-10s %-12s %-8s %-12s %-6s %s\n" \
  "Region" "CosmosDB" "PgFlex" "MySQLFlex" "Redis" "SQLServer" "ACI" "Status"
echo "$(printf '%0.s-' {1..85})"

ALL_OK=()
PARTIAL=()

for region in "${CANDIDATES[@]}"; do
  display="${DISPLAY[$region]}"

  ok_cosmos=$(echo "$COSMOS_LOCS" | grep -ic "$display")
  ok_psql=$(echo "$PSQL_LOCS" | grep -ic "$display")
  ok_mysql=$(echo "$MYSQL_LOCS" | grep -ic "$display")
  ok_redis=$(echo "$REDIS_LOCS" | grep -ic "$display")
  ok_sql=$(echo "$SQL_LOCS" | grep -ic "$display")
  ok_aci=$(echo "$ACI_LOCS" | grep -ic "$display")

  fmt_svc() { [ "$1" -gt 0 ] && echo "✅" || echo "❌"; }

  all_ok=true
  for v in "$ok_cosmos" "$ok_psql" "$ok_mysql" "$ok_redis" "$ok_sql" "$ok_aci"; do
    [ "$v" -eq 0 ] && all_ok=false
  done

  if $all_ok; then
    status="✅ ALL GOOD"
    ALL_OK+=("$region")
  else
    missing=""
    [ "$ok_cosmos" -eq 0 ] && missing+="CosmosDB "
    [ "$ok_psql" -eq 0 ]   && missing+="PgFlex "
    [ "$ok_mysql" -eq 0 ]  && missing+="MySQLFlex "
    [ "$ok_redis" -eq 0 ]  && missing+="Redis "
    [ "$ok_sql" -eq 0 ]    && missing+="SQLServer "
    [ "$ok_aci" -eq 0 ]    && missing+="ACI "
    status="⚠  Missing: $missing"
    PARTIAL+=("$region")
  fi

  printf "%-20s %-10s %-10s %-12s %-8s %-12s %-6s %s\n" \
    "$region" \
    "$(fmt_svc $ok_cosmos)" "$(fmt_svc $ok_psql)" "$(fmt_svc $ok_mysql)" \
    "$(fmt_svc $ok_redis)" "$(fmt_svc $ok_sql)" "$(fmt_svc $ok_aci)" \
    "$status"
done

echo ""
echo "==========================================="
echo " RECOMMENDATION"
echo "==========================================="
if [ ${#ALL_OK[@]} -gt 0 ]; then
  echo ""
  echo "Regions where both B1 App Service AND all required services are available:"
  for r in "${ALL_OK[@]}"; do
    echo "  ✅ $r  (${DISPLAY[$r]})"
  done
  echo ""
  echo "Best pick for EU data residency:    francecentral or swedencentral or norwayeast"
  echo "Best pick for US workloads:         centralus or westus2 or canadacentral"
  echo "Best pick for APAC workloads:       australiaeast or southeastasia"
fi
if [ ${#PARTIAL[@]} -gt 0 ]; then
  echo ""
  echo "Regions where B1 is OK but one or more services are missing:"
  for r in "${PARTIAL[@]}"; do echo "  ⚠  $r"; done
fi
