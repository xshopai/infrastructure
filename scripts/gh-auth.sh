#!/bin/bash
# ==============================================================================
# GitHub CLI Authentication Script
# ==============================================================================
# This script authenticates GitHub CLI for use with automation scripts.
# ==============================================================================

set -e

# Unset GH_TOKEN if present (can interfere with gh auth login)
if [ -n "$GH_TOKEN" ]; then
    echo "⚠️  Unsetting GH_TOKEN environment variable (can interfere with authentication)"
    unset GH_TOKEN
fi

echo "🔐 GitHub CLI Authentication"
echo "============================"
echo ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed"
    echo "   Install from: https://cli.github.com/"
    exit 1
fi

# Check current auth status
if gh auth status &> /dev/null; then
    echo "✅ Already authenticated to GitHub"
    gh auth status
    exit 0
fi

echo ""
echo "📋 Authenticating to GitHub..."
echo ""
echo "You'll need to:"
echo "1. Choose authentication method (browser or token)"
echo "2. Select 'GitHub.com' as the account"
echo "3. Select protocol: HTTPS"
echo "4. Authenticate and authorize the CLI"
echo ""

# Authenticate with GitHub
gh auth login

echo ""
echo "✅ GitHub CLI authentication complete!"
echo ""
echo "Verify authentication:"
gh auth status
