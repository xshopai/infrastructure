#!/bin/bash

################################################################################
# Setup GitHub Repository Secrets for xShopAI Bicep Infrastructure Deployment
#
# Generates secure passwords/tokens and adds them to GitHub repository secrets.
# These secrets are required by the deploy-app-service-bicep.yml workflow.
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - OpenSSL installed
#   - Write access to the infrastructure repository
#
# Usage:
#   ./setup-secrets.sh                    # Interactive mode
#   ./setup-secrets.sh --repo xshopai/infrastructure --auto
#   ./setup-secrets.sh --dry-run          # Show what would be created
#
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_REPO="xshopai/infrastructure"
DRY_RUN=false
AUTO_CONFIRM=false

################################################################################
# Helper Functions
################################################################################

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"; }

# Generate a secure password (alphanumeric only for database compatibility)
generate_password() {
    local length=${1:-24}
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$length"
}

# Generate SQL Server password (requires uppercase, lowercase, digit, special char)
generate_sql_password() {
    local prefix="Xshop"
    local random=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)
    echo "${prefix}${random}!"
}

# Generate a secure token (64 chars for API tokens)
generate_token() {
    openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c 64
}

################################################################################
# Parse Arguments
################################################################################

REPO="$DEFAULT_REPO"

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --auto)
            AUTO_CONFIRM=true
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [options]

Generates and sets up GitHub repository secrets for the Bicep infrastructure workflow.

Options:
  --repo OWNER/REPO   Target repository (default: xshopai/infrastructure)
  --dry-run           Generate secrets and show them without adding to GitHub
  --auto              Skip confirmation prompts
  --help, -h          Show this help message

Examples:
  # Interactive setup
  $0

  # Dry run to see what secrets would be generated
  $0 --dry-run

  # Fully automated setup
  $0 --auto

Required Secrets (will be generated):
  - POSTGRES_ADMIN_PASSWORD   PostgreSQL admin password
  - MYSQL_ADMIN_PASSWORD      MySQL admin password
  - SQL_ADMIN_PASSWORD        SQL Server admin password
  - RABBITMQ_PASSWORD         RabbitMQ admin password
  - JWT_SECRET                JWT signing key
  - ADMIN_SERVICE_TOKEN       Admin service API token
  - AUTH_SERVICE_TOKEN        Auth service API token
  - USER_SERVICE_TOKEN        User service API token
  - CART_SERVICE_TOKEN        Cart service API token
  - ORDER_SERVICE_TOKEN       Order service API token
  - PRODUCT_SERVICE_TOKEN     Product service API token
  - WEB_BFF_TOKEN             Web BFF API token
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
# Prerequisites Check
################################################################################

log_header "Prerequisites Check"

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is not installed"
    echo "Install from: https://cli.github.com/"
    exit 1
fi
log_success "GitHub CLI found"

# Check for OpenSSL
if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL is not installed"
    exit 1
fi
log_success "OpenSSL found"

# Check GitHub CLI authentication
if ! gh auth status &> /dev/null; then
    log_error "Not authenticated with GitHub CLI"
    echo "Run: gh auth login"
    exit 1
fi
log_success "GitHub CLI authenticated"

# Verify repository access
if [ "$DRY_RUN" = false ]; then
    if ! gh repo view "$REPO" &> /dev/null; then
        log_error "Cannot access repository: $REPO"
        echo "Ensure you have write access to the repository"
        exit 1
    fi
    log_success "Repository access verified: $REPO"
fi

################################################################################
# Generate Secrets
################################################################################

log_header "Generating Secrets"

# Database passwords (alphanumeric for compatibility)
POSTGRES_ADMIN_PASSWORD=$(generate_password 24)
MYSQL_ADMIN_PASSWORD=$(generate_password 24)
SQL_ADMIN_PASSWORD=$(generate_sql_password)  # SQL Server needs special format
RABBITMQ_PASSWORD=$(generate_password 24)

# JWT and API tokens (64 chars)
JWT_SECRET=$(generate_token)
ADMIN_SERVICE_TOKEN=$(generate_token)
AUTH_SERVICE_TOKEN=$(generate_token)
USER_SERVICE_TOKEN=$(generate_token)
CART_SERVICE_TOKEN=$(generate_token)
ORDER_SERVICE_TOKEN=$(generate_token)
PRODUCT_SERVICE_TOKEN=$(generate_token)
WEB_BFF_TOKEN=$(generate_token)

log_success "Generated 12 secure secrets"

################################################################################
# Display Generated Secrets
################################################################################

log_header "Generated Secrets"

echo -e "${YELLOW}Database Passwords:${NC}"
echo -e "  POSTGRES_ADMIN_PASSWORD: ${GREEN}${POSTGRES_ADMIN_PASSWORD}${NC}"
echo -e "  MYSQL_ADMIN_PASSWORD:    ${GREEN}${MYSQL_ADMIN_PASSWORD}${NC}"
echo -e "  SQL_ADMIN_PASSWORD:      ${GREEN}${SQL_ADMIN_PASSWORD}${NC}"
echo -e "  RABBITMQ_PASSWORD:       ${GREEN}${RABBITMQ_PASSWORD}${NC}"
echo ""
echo -e "${YELLOW}JWT & API Tokens:${NC}"
echo -e "  JWT_SECRET:              ${GREEN}${JWT_SECRET}${NC}"
echo -e "  ADMIN_SERVICE_TOKEN:     ${GREEN}${ADMIN_SERVICE_TOKEN}${NC}"
echo -e "  AUTH_SERVICE_TOKEN:      ${GREEN}${AUTH_SERVICE_TOKEN}${NC}"
echo -e "  USER_SERVICE_TOKEN:      ${GREEN}${USER_SERVICE_TOKEN}${NC}"
echo -e "  CART_SERVICE_TOKEN:      ${GREEN}${CART_SERVICE_TOKEN}${NC}"
echo -e "  ORDER_SERVICE_TOKEN:     ${GREEN}${ORDER_SERVICE_TOKEN}${NC}"
echo -e "  PRODUCT_SERVICE_TOKEN:   ${GREEN}${PRODUCT_SERVICE_TOKEN}${NC}"
echo -e "  WEB_BFF_TOKEN:           ${GREEN}${WEB_BFF_TOKEN}${NC}"

################################################################################
# Dry Run Exit
################################################################################

if [ "$DRY_RUN" = true ]; then
    log_header "Dry Run Complete"
    echo "Secrets were generated but NOT added to GitHub."
    echo ""
    echo "To add manually, go to:"
    echo "  https://github.com/${REPO}/settings/secrets/actions"
    echo ""
    echo "Or run this script without --dry-run to add automatically."
    exit 0
fi

################################################################################
# Confirmation
################################################################################

if [ "$AUTO_CONFIRM" = false ]; then
    echo ""
    log_warning "These secrets will be added to: $REPO"
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        exit 0
    fi
fi

################################################################################
# Add Secrets to GitHub
################################################################################

log_header "Adding Secrets to GitHub Repository"

add_secret() {
    local name=$1
    local value=$2
    
    echo -n "  Adding $name... "
    if echo "$value" | gh secret set "$name" --repo "$REPO" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Add all secrets
add_secret "POSTGRES_ADMIN_PASSWORD" "$POSTGRES_ADMIN_PASSWORD"
add_secret "MYSQL_ADMIN_PASSWORD" "$MYSQL_ADMIN_PASSWORD"
add_secret "SQL_ADMIN_PASSWORD" "$SQL_ADMIN_PASSWORD"
add_secret "RABBITMQ_PASSWORD" "$RABBITMQ_PASSWORD"
add_secret "JWT_SECRET" "$JWT_SECRET"
add_secret "ADMIN_SERVICE_TOKEN" "$ADMIN_SERVICE_TOKEN"
add_secret "AUTH_SERVICE_TOKEN" "$AUTH_SERVICE_TOKEN"
add_secret "USER_SERVICE_TOKEN" "$USER_SERVICE_TOKEN"
add_secret "CART_SERVICE_TOKEN" "$CART_SERVICE_TOKEN"
add_secret "ORDER_SERVICE_TOKEN" "$ORDER_SERVICE_TOKEN"
add_secret "PRODUCT_SERVICE_TOKEN" "$PRODUCT_SERVICE_TOKEN"
add_secret "WEB_BFF_TOKEN" "$WEB_BFF_TOKEN"

################################################################################
# Success
################################################################################

log_header "Setup Complete! 🎉"

echo "All 12 secrets have been added to: $REPO"
echo ""
echo "You can now run the Bicep deployment workflow:"
echo "  gh workflow run deploy-app-service-bicep.yml --repo $REPO -f environment=dev -f suffix=bicep"
echo ""
echo "Or via GitHub UI:"
echo "  https://github.com/${REPO}/actions/workflows/deploy-app-service-bicep.yml"
echo ""
log_warning "These secrets are stored securely in GitHub and cannot be viewed again."
log_warning "If you need to regenerate, run this script again (it will overwrite)."
