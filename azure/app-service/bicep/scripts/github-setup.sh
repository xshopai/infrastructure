#!/bin/bash

################################################################################
# Setup GitHub Environments for xshopai Platform
#
# Creates 'development' and 'production' environments in all service repositories.
# These environments are required for GitHub Actions workflows to deploy services.
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Org admin permissions (to create environments)
#
# Usage:
#   ./setup-github-environments.sh [--org ORGANIZATION] [--repos "repo1 repo2..."]
#
################################################################################

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
DEFAULT_ORG="xshopai"
DEFAULT_ENVIRONMENTS=("development" "production")

# All service repositories that need environments
DEFAULT_REPOS=(
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
    "infrastructure"  # Important: infrastructure repo needs environments too
)

################################################################################
# Parse Arguments
################################################################################

ORG="$DEFAULT_ORG"
REPOS=("${DEFAULT_REPOS[@]}")
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --org)
            ORG="$2"
            shift 2
            ;;
        --repos)
            IFS=' ' read -r -a REPOS <<< "$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [options]

Options:
  --org ORG         GitHub organization name (default: xshopai)
  --repos "r1 r2"   Space-separated list of repos (default: all services)
  --dry-run         Show what would be done without making changes
  --help, -h        Show this help message

Examples:
  # Setup all repos with default settings
  $0

  # Setup specific repos
  $0 --repos "auth-service user-service"

  # Dry run to see what would happen
  $0 --dry-run
EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

################################################################################
# Check Prerequisites
################################################################################

check_github_cli() {
    log_header "🔍 Checking Prerequisites"
    
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is required but not installed"
        log_info "Install from: https://cli.github.com/"
        exit 1
    fi
    
    log_success "GitHub CLI found: $(gh --version | head -n1)"
    
    # Check authentication
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated to GitHub"
        log_info "Run: gh auth login"
        exit 1
    fi
    
    log_success "Authenticated to GitHub"
    echo ""
}

################################################################################
# Create Environment in a Repository
################################################################################

create_environment() {
    local repo=$1
    local env_name=$2
    local full_repo="$ORG/$repo"
    
    log_info "Creating '$env_name' in $repo..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create environment: $full_repo/$env_name"
        return 0
    fi
    
    # Check if repo exists
    if ! gh repo view "$full_repo" &> /dev/null; then
        log_warning "Repository $full_repo not found - skipping"
        return 1
    fi
    
    # Create environment using GitHub API
    # Note: gh CLI doesn't have direct environment commands, so we use API
    local response
    response=$(gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        "/repos/$full_repo/environments/$env_name" \
        -f wait_timer=0 \
        2>&1) || {
        log_warning "Failed to create environment (may already exist)"
        return 0  # Don't fail if already exists
    }
    
    # Configure protection rules for production
    if [ "$env_name" = "production" ]; then
        log_info "  → Configuring protection rules for production..."
        
        # Get organization admins for reviewers
        local org_admins
        org_admins=$(gh api "/orgs/$ORG/members?role=admin" --jq '.[].login' 2>/dev/null || echo "")
        
        if [ -z "$org_admins" ]; then
            # Fallback to current user if org API fails
            org_admins=$(gh api user -q .login)
            log_warning "Could not fetch org admins, using current user only"
        fi
        
        # Get first 2 admins for reviewers
        local reviewer_ids=()
        local count=0
        while IFS= read -r admin_login; do
            if [ $count -ge 2 ]; then break; fi
            local admin_id=$(gh api "/users/$admin_login" -q .id 2>/dev/null)
            if [ -n "$admin_id" ]; then
                reviewer_ids+=("$admin_id")
                ((count++))
            fi
        done <<< "$org_admins"
        
        # Build reviewer JSON
        local reviewers_json="["
        for ((i=0; i<${#reviewer_ids[@]}; i++)); do
            if [ $i -gt 0 ]; then reviewers_json="${reviewers_json},"; fi
            reviewers_json="${reviewers_json}{\"type\":\"User\",\"id\":${reviewer_ids[$i]}}"
        done
        reviewers_json="${reviewers_json}]"
        
        # Configure production environment protection
        gh api \
            --method PUT \
            -H "Accept: application/vnd.github+json" \
            "/repos/$full_repo/environments/$env_name" \
            -f "wait_timer=0" \
            -f "prevent_self_review=true" \
            -F "reviewers=$reviewers_json" \
            -f "deployment_branch_policy[protected_branches]=true" \
            -f "deployment_branch_policy[custom_branch_policies]=false" \
            2>&1 | grep -q "message" && log_warning "  ⚠ Limited permissions (some rules may not apply)" || log_success "  ✓ Protection rules configured"
    fi
    
    log_success "  ✓ Environment '$env_name' ready"
}

################################################################################
# Main Processing
################################################################################

main() {
    log_header "🌍 GitHub Environment Setup"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    echo "Organization: $ORG"
    echo "Environments: ${DEFAULT_ENVIRONMENTS[*]}"
    echo "Repositories: ${#REPOS[@]}"
    echo ""
    
    # Check prerequisites
    check_github_cli
    
    # Counters
    local total_created=0
    local total_skipped=0
    local total_failed=0
    
    # Process each repository
    for repo in "${REPOS[@]}"; do
        log_header "Repository: $repo"
        
        local repo_success=0
        
        # Create each environment
        for env in "${DEFAULT_ENVIRONMENTS[@]}"; do
            if create_environment "$repo" "$env"; then
                ((repo_success++))
            else
                ((total_failed++))
            fi
        done
        
        if [ "$repo_success" -eq "${#DEFAULT_ENVIRONMENTS[@]}" ]; then
            ((total_created++))
        fi
        
        echo ""
    done
    
    # Summary
    log_header "📊 Summary"
    echo "Repositories processed: ${#REPOS[@]}"
    echo "Environments per repo: ${#DEFAULT_ENVIRONMENTS[@]}"
    echo "Total environments: $((${#REPOS[@]} * ${#DEFAULT_ENVIRONMENTS[@]}))"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_info "This was a dry run. Re-run without --dry-run to apply changes."
    else
        log_success "✅ Environment setup complete!"
        echo ""
        log_info "Next steps:"
        echo "  1. Verify environments in GitHub:"
        echo "     https://github.com/$ORG/<repo>/settings/environments"
        echo ""
        echo "  2. Environments are now available for workflow deployments"
        echo ""
        echo "  3. Configure environment-specific secrets if needed:"
        echo "     gh secret set SECRET_NAME --env production --repo $ORG/repo-name"
    fi
    
    echo ""
}

################################################################################
# Run Main
################################################################################

main "$@"
