#!/bin/bash
# ============================================================================
# GitHub Environments Setup Script for xshopai Platform
# ============================================================================
# This script creates GitHub environments (dev and prod) in all service
# repositories. These environments are REQUIRED for OIDC authentication.
#
# Why Environments Are Required:
#   - Azure federated credentials match on subject: "environment:dev|prod"
#   - Without environments, GitHub workflows can't authenticate to Azure
#   - Environments enable deployment protection rules (manual approval for prod)
#
# Prerequisites:
#   - GitHub CLI installed and authenticated (gh auth login)
#   - GitHub org admin permissions
#
# Usage:
#   chmod +x setup-github-environments.sh
#   ./setup-github-environments.sh
# ============================================================================

set -e  # Exit on error

# ============================================================================
# CONFIGURATION
# ============================================================================
GITHUB_ORG="xshopai"

echo "============================================"
echo "GitHub Environments Setup for xshopai"
echo "============================================"
echo ""

# Check if GitHub CLI is authenticated
if ! gh auth status > /dev/null 2>&1; then
    echo "❌ Error: GitHub CLI not authenticated. Please run 'gh auth login' first."
    exit 1
fi

echo "📋 This script will create 'dev' and 'prod' environments in all repositories."
echo "   These environments are REQUIRED for Azure OIDC authentication to work!"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# ============================================================================
# List of all repositories
# ============================================================================

REPOS=(
    "infrastructure"
    "admin-service"
    "admin-ui"
    "audit-service"
    "auth-service"
    "cart-service"
    "chat-service"
    "customer-ui"
    "inventory-service"
    "notification-service"
    "order-processor-service"
    "order-service"
    "payment-service"
    "product-service"
    "review-service"
    "user-service"
    "web-bff"
)

ENVIRONMENTS=("dev" "prod")

# ============================================================================
# Create environments in each repository
# ============================================================================

echo ""
echo "🔧 Creating environments in repositories..."
echo ""

SUCCESS_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

for repo in "${REPOS[@]}"; do
    echo "📦 Processing: ${GITHUB_ORG}/${repo}"
    
    # Check if repo exists
    if ! gh repo view "${GITHUB_ORG}/${repo}" > /dev/null 2>&1; then
        echo "   ⚠️  Repository does not exist - skipping"
        ((SKIP_COUNT++))
        echo ""
        continue
    fi
    
    for env in "${ENVIRONMENTS[@]}"; do
        # Check if environment already exists
        EXISTING=$(gh api "repos/${GITHUB_ORG}/${repo}/environments/${env}" 2>/dev/null || echo "")
        
        if [ -n "$EXISTING" ]; then
            echo "   ✅ Environment '${env}' already exists"
        else
            # Create environment
            # For prod, enable protection rules (wait_timer + reviewers could be added later)
            if [ "$env" == "prod" ]; then
                gh api -X PUT "repos/${GITHUB_ORG}/${repo}/environments/${env}" \
                    --input - <<EOF > /dev/null 2>&1
{
    "wait_timer": 0,
    "prevent_self_review": false,
    "reviewers": []
}
EOF
            else
                # Dev environment - no protection
                gh api -X PUT "repos/${GITHUB_ORG}/${repo}/environments/${env}" > /dev/null 2>&1
            fi
            
            if [ $? -eq 0 ]; then
                echo "   ✅ Created environment '${env}'"
                ((SUCCESS_COUNT++))
            else
                echo "   ❌ Failed to create environment '${env}'"
                ((ERROR_COUNT++))
            fi
        fi
    done
    echo ""
done

# ============================================================================
# Summary
# ============================================================================

echo "============================================"
echo "✅ Environment Setup Complete!"
echo "============================================"
echo ""
echo "📊 Summary:"
echo "   Repositories processed: ${#REPOS[@]}"
echo "   Environments created: ${SUCCESS_COUNT}"
echo "   Skipped (repo not found): ${SKIP_COUNT}"
echo "   Errors: ${ERROR_COUNT}"
echo ""

if [ $ERROR_COUNT -gt 0 ]; then
    echo "⚠️  Some environments failed to create. Check errors above."
    echo ""
fi

echo "============================================"
echo "🎯 What Was Created"
echo "============================================"
echo ""
echo "Each repository now has 2 environments:"
echo "   • dev  - Development environment (no protection)"
echo "   • prod - Production environment (can add manual approval later)"
echo ""
echo "These environments enable:"
echo "   ✅ Azure OIDC authentication (required!)"
echo "   ✅ Environment-specific secrets/variables"
echo "   ✅ Deployment protection rules"
echo "   ✅ Environment-specific workflows"
echo ""

echo "============================================"
echo "🔐 Verifying OIDC Configuration"
echo "============================================"
echo ""
echo "Checking if repos use environment-only OIDC..."
echo ""

for repo in "${REPOS[@]}"; do
    if gh repo view "${GITHUB_ORG}/${repo}" > /dev/null 2>&1; then
        OIDC_CONFIG=$(gh api "repos/${GITHUB_ORG}/${repo}/actions/oidc/customization/sub" 2>/dev/null || echo '{"use_default":true}')
        USE_DEFAULT=$(echo "$OIDC_CONFIG" | jq -r '.use_default')
        
        if [ "$USE_DEFAULT" == "false" ]; then
            echo "   ✅ ${repo} (environment-only OIDC)"
        else
            echo "   ⚠️  ${repo} (using default OIDC - run setup-azure-oidc.sh)"
        fi
    fi
done

echo ""
echo "============================================"
echo "🚀 Next Steps"
echo "============================================"
echo ""
echo "1. ✅ GitHub environments created"
echo "2. ⏭️  Verify OIDC configuration (see above)"
echo "3. ⏭️  Configure organization secrets if not done yet:"
echo "   ./setup-github-secrets.sh"
echo "4. ⏭️  Deploy platform infrastructure:"
echo "   gh workflow run deploy-platform-infrastructure.yml"
echo "5. ⏭️  Deploy microservices to each environment"
echo ""
echo "To verify environments were created:"
echo "   gh api repos/${GITHUB_ORG}/product-service/environments"
echo ""
