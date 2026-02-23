#!/bin/bash
# =============================================================================
# Ensure Critical Infrastructure Services are Running
# =============================================================================
# Run this before deploying applications or when troubleshooting
# Usage: ./ensure-services-running.sh <resource-group> <environment>

set -e

RESOURCE_GROUP="${1:-rg-xshopai-development}"
ENV="${2:-development}"

echo "======================================"
echo "Checking Infrastructure Services"
echo "Environment: $ENV"
echo "Resource Group: $RESOURCE_GROUP"
echo "======================================"
echo ""

# =============================================================================
# Check and Start PostgreSQL
# =============================================================================
echo "🔍 Checking PostgreSQL..."
POSTGRES_NAME="psql-xshopai-${ENV}"
POSTGRES_STATE=$(az postgres flexible-server show \
  --name "$POSTGRES_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "state" -o tsv 2>&1 | grep -v "Deprecation" || echo "NotFound")

if [ "$POSTGRES_STATE" == "NotFound" ]; then
  echo "❌ PostgreSQL server not found: $POSTGRES_NAME"
  exit 1
elif [ "$POSTGRES_STATE" == "Stopped" ]; then
  echo "⚠️  PostgreSQL is STOPPED. Starting..."
  az postgres flexible-server start \
    --name "$POSTGRES_NAME" \
    --resource-group "$RESOURCE_GROUP"
  echo "✅ PostgreSQL started successfully"
elif [ "$POSTGRES_STATE" == "Starting" ]; then
  echo "🔄 PostgreSQL is starting..."
  echo "   Waiting for it to become Ready..."
  sleep 10
elif [ "$POSTGRES_STATE" == "Ready" ]; then
  echo "✅ PostgreSQL is running"
else
  echo "⚠️  PostgreSQL state: $POSTGRES_STATE"
fi

echo ""

# =============================================================================
# Check RabbitMQ (Azure Container Instance)
# =============================================================================
echo "🔍 Checking RabbitMQ..."
RABBITMQ_NAME="aci-rabbitmq-${ENV}"
RABBITMQ_STATE=$(az container show \
  --name "$RABBITMQ_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "instanceView.state" -o tsv 2>&1 | grep -v "Deprecation" || echo "NotFound")

if [ "$RABBITMQ_STATE" == "NotFound" ]; then
  echo "❌ RabbitMQ container not found: $RABBITMQ_NAME"
  exit 1
elif [ "$RABBITMQ_STATE" == "Stopped" ]; then
  echo "⚠️  RabbitMQ is STOPPED. Starting..."
  az container start \
    --name "$RABBITMQ_NAME" \
    --resource-group "$RESOURCE_GROUP"
  echo "✅ RabbitMQ started successfully"
elif [ "$RABBITMQ_STATE" == "Running" ]; then
  echo "✅ RabbitMQ is running"
else
  echo "⚠️  RabbitMQ state: $RABBITMQ_STATE"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "======================================"
echo "✅ All infrastructure services checked"
echo "======================================"
echo ""
echo "💡 Tip: Add this script to your deployment pipeline before deploying apps"
echo ""
