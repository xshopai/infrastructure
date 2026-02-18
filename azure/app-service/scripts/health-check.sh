#!/bin/bash

# XShopAI Platform Health Check Script
# This script checks the health of all microservices

echo "════════════════════════════════════════════════"
echo "   XShopAI Platform Health Check Report"
echo "   $(date)"
echo "════════════════════════════════════════════════"
echo ""

# Function to check health endpoint
check_health() {
    local service=$1
    local port=$2
    local endpoint=$3
    local expected_status=${4:-200}
    
    response=$(curl -s -w "\n%{http_code}" http://localhost:$port$endpoint 2>/dev/null)
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo "✅ $service (port $port) - HEALTHY"
        return 0
    else
        echo "❌ $service (port $port) - UNHEALTHY (HTTP $http_code)"
        if [ -n "$body" ]; then
            echo "   Response: $(echo "$body" | tr '\n' ' ' | cut -c1-100)"
        fi
        return 1
    fi
}

declare -i healthy_count=0
declare -i unhealthy_count=0

echo "🔍 Checking Node.js Services..."
echo "────────────────────────────────────────────────"

# User Service (Auth Service
check_health "Auth Service" 8004 "/health/ready" && ((healthy_count++)) || ((unhealthy_count++))

# Admin Service
check_health "Admin Service" 8003 "/health/ready" && ((healthy_count++)) || ((unhealthy_count++))

# Review Service
check_health "Review Service" 8010 "/health/ready" && ((healthy_count++)) || ((unhealthy_count++))

# Notification Service
check_health "Notification Service" 8011 "/health/ready" && ((healthy_count++)) || ((unhealthy_count++))

# Chat Service
check_health "Chat Service" 8013 "/health/ready" && ((healthy_count++)) || ((unhealthy_count++))

# Web BFF
check_health "Web BFF" 8014 "/health/ready" && ((healthy_count++)) || ((unhealthy_count++))

echo ""
echo "🐍 Checking Python Services..."
echo "────────────────────────────────────────────────"

# Product Service (FastAPI)
check_health "Product Service" 8001 "/api/health" && ((healthy_count++)) || ((unhealthy_count++))

# Inventory Service (FastAPI)
check_health "Inventory Service" 8005 "/api/health" && ((healthy_count++)) || ((unhealthy_count++))

echo ""
echo "☕ Checking Java Services..."
echo "────────────────────────────────────────────────"

# Cart Service (Spring Boot)
check_health "Cart Service" 8008 "/actuator/health" && ((healthy_count++)) || ((unhealthy_count++))

# Order Processor Service (Spring Boot)
check_health "Order Processor Service" 8007 "/actuator/health" && ((healthy_count++)) || ((unhealthy_count++))

echo ""
echo "🔷 Checking .NET Services..."
echo "────────────────────────────────────────────────"

# Order Service (.NET)
check_health "Order Service" 8006 "/health" && ((healthy_count++)) || ((unhealthy_count++))

# Payment Service (.NET)
check_health "Payment Service" 8009 "/health" && ((healthy_count++)) || ((unhealthy_count++))

echo ""
echo "📊 Checking TypeScript Services..."
echo "────────────────────────────────────────────────"

# Audit Service
check_health "Audit Service" 8012 "/health" && ((healthy_count++)) || ((unhealthy_count++))

echo ""
echo "🌐 Checking UI Services..."
echo "────────────────────────────────────────────────"

# Customer UI
response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
if [ "$response_code" = "200" ]; then
    echo "✅ Customer UI (port 3000) - HEALTHY"
    ((healthy_count++))
else
    echo "❌ Customer UI (port 3000) - UNHEALTHY (HTTP $response_code)"
    ((unhealthy_count++))
fi

# Admin UI
response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001 2>/dev/null)
if [ "$response_code" = "200" ]; then
    echo "✅ Admin UI (port 3001) - HEALTHY"
    ((healthy_count++))
else
    echo "❌ Admin UI (port 3001) - UNHEALTHY (HTTP $response_code)"
    ((unhealthy_count++))
fi

echo ""
echo "════════════════════════════════════════════════"
echo "   SUMMARY"
echo "════════════════════════════════════════════════"
echo "✅ Healthy Services: $healthy_count"
echo "❌ Unhealthy Services: $unhealthy_count"
echo "📊 Total Services: $((healthy_count + unhealthy_count))"

if [ $unhealthy_count -eq 0 ]; then
    echo ""
    echo "🎉 All services are healthy!"
    exit 0
else
    echo ""
    echo "⚠️  Some services need attention!"
    exit 1
fi
