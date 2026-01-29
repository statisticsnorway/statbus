#!/bin/bash
#
# install-statbus.sh
# STATBUS Installation Script for Ubuntu 24.04 LTS
#
# Prerequisites:
#   - Run harden-ubuntu-lts-24.sh first (or manually install Docker)
#   - Run as devops user (or any user with sudo and docker access)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/devops/install-statbus.sh -o install-statbus.sh
#   chmod +x install-statbus.sh
#   ./install-statbus.sh
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

STATBUS_REPO="https://github.com/statisticsnorway/statbus.git"
INSTALL_DIR="${STATBUS_DIR:-$HOME/statbus}"

# =============================================================================
# Colors and Formatting
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_header "Checking Prerequisites"
    
    local missing=()
    
    # Check Docker
    if command -v docker &>/dev/null; then
        log_success "Docker installed: $(docker --version)"
    else
        missing+=("docker")
        log_error "Docker not found"
    fi
    
    # Check Docker Compose
    if docker compose version &>/dev/null; then
        log_success "Docker Compose installed: $(docker compose version --short)"
    else
        missing+=("docker-compose")
        log_error "Docker Compose not found"
    fi
    
    # Check if user can run docker without sudo
    if docker ps &>/dev/null; then
        log_success "User can run Docker commands"
    else
        log_error "User cannot run Docker commands (not in docker group?)"
        missing+=("docker-access")
    fi
    
    # Check Git
    if command -v git &>/dev/null; then
        log_success "Git installed: $(git --version)"
    else
        missing+=("git")
        log_error "Git not found"
    fi
    
    # Check OpenSSL (needed for PFX certificate conversion)
    if command -v openssl &>/dev/null; then
        log_success "OpenSSL installed: $(openssl version)"
    else
        missing+=("openssl")
        log_error "OpenSSL not found"
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_error "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Please run the hardening script first:"
        echo "  curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/devops/harden-ubuntu-lts-24.sh -o harden.sh"
        echo "  chmod +x harden.sh"
        echo "  sudo ./harden.sh"
        echo ""
        echo "Or install the missing components manually."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# =============================================================================
# Install Crystal
# =============================================================================

install_crystal() {
    log_header "Installing Crystal Language"
    
    if command -v crystal &>/dev/null; then
        log_success "Crystal already installed: $(crystal --version | head -1)"
        return 0
    fi
    
    log "Installing Crystal via official installer..."
    curl -fsSL https://crystal-lang.org/install.sh | sudo bash
    
    # Verify installation
    if command -v crystal &>/dev/null; then
        log_success "Crystal installed: $(crystal --version | head -1)"
        log_success "Shards installed: $(shards --version)"
    else
        log_error "Crystal installation failed"
        exit 1
    fi
}

# =============================================================================
# Clone Repository
# =============================================================================

clone_repository() {
    log_header "Cloning STATBUS Repository"
    
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        log "Repository already exists at $INSTALL_DIR"
        
        pushd "$INSTALL_DIR" > /dev/null
        local current_branch
        current_branch=$(git branch --show-current)
        log "Current branch: $current_branch"
        
        log "Fetching latest changes..."
        git fetch origin
        
        local local_rev remote_rev
        local_rev=$(git rev-parse HEAD)
        remote_rev=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")
        
        if [[ "$local_rev" != "$remote_rev" && -n "$remote_rev" ]]; then
            log_warn "Remote has new commits. Run 'git pull' to update."
        else
            log_success "Repository is up to date"
        fi
        popd > /dev/null
        return 0
    fi
    
    log "Cloning from $STATBUS_REPO..."
    git clone "$STATBUS_REPO" "$INSTALL_DIR"
    
    pushd "$INSTALL_DIR" > /dev/null
    
    log "Configuring git hooks..."
    git config core.hooksPath devops/githooks
    
    popd > /dev/null
    
    log_success "Repository cloned to $INSTALL_DIR"
}

# =============================================================================
# Build CLI Tool
# =============================================================================

build_cli() {
    log_header "Building STATBUS CLI Tool"
    
    pushd "$INSTALL_DIR/cli" > /dev/null
    
    if [[ -f "bin/statbus" ]]; then
        log "CLI binary exists, checking if rebuild needed..."
        
        # Check if source is newer than binary
        local newest_source
        newest_source=$(find src -name "*.cr" -newer bin/statbus 2>/dev/null | head -1)
        
        if [[ -z "$newest_source" ]]; then
            log_success "CLI binary is up to date"
            popd > /dev/null
            return 0
        fi
        
        log "Source files changed, rebuilding..."
    fi
    
    log "Installing Crystal dependencies..."
    shards install
    
    log "Building statbus CLI (this may take a minute)..."
    shards build --release
    
    if [[ -x "bin/statbus" ]]; then
        log_success "CLI built successfully"
    else
        log_error "CLI build failed"
        exit 1
    fi
    
    popd > /dev/null
}

# =============================================================================
# Detect HTTP-blocked Networks
# =============================================================================

detect_http_blocked() {
    log_header "Network Configuration Check"
    
    log "Checking network connectivity..."
    
    local http_works=false
    local https_works=false
    
    # Test HTTP connectivity (5 second timeout)
    if curl -sf --connect-timeout 5 http://archive.ubuntu.com/ubuntu/dists/jammy/Release.gpg -o /dev/null 2>/dev/null; then
        http_works=true
    fi
    
    # Test HTTPS connectivity
    if curl -sf --connect-timeout 5 https://archive.ubuntu.com/ubuntu/dists/jammy/Release.gpg -o /dev/null 2>/dev/null; then
        https_works=true
    fi
    
    if [[ "$http_works" == "true" ]]; then
        log_success "HTTP connectivity works"
        return 1  # HTTP not blocked
    elif [[ "$https_works" == "true" ]]; then
        log_warn "HTTP traffic appears to be blocked on this network"
        log_success "HTTPS connectivity works"
        return 0  # HTTP is blocked
    else
        log_warn "Both HTTP and HTTPS connectivity tests failed"
        log_warn "This may indicate a network issue or firewall configuration"
        return 1  # Can't determine, assume HTTP is not specifically blocked
    fi
}

configure_https_only() {
    local env_config="$INSTALL_DIR/.env.config"
    
    if [[ ! -f "$env_config" ]]; then
        log_warn ".env.config not found, skipping HTTPS-only configuration"
        return 1
    fi
    
    log "Updating .env.config with APT_USE_HTTPS_ONLY=true..."
    
    # Update or add APT_USE_HTTPS_ONLY
    if grep -q "^APT_USE_HTTPS_ONLY=" "$env_config"; then
        sed -i.bak "s|^APT_USE_HTTPS_ONLY=.*|APT_USE_HTTPS_ONLY=true|" "$env_config"
    else
        echo "APT_USE_HTTPS_ONLY=true" >> "$env_config"
    fi
    rm -f "$env_config.bak"
    
    log_success "Set APT_USE_HTTPS_ONLY=true in .env.config"
    
    # Regenerate configuration
    log "Regenerating configuration..."
    if "$INSTALL_DIR/devops/manage-statbus.sh" generate-config >/dev/null 2>&1; then
        log_success "Configuration regenerated"
    else
        log_warn "Failed to regenerate configuration. Run manually:"
        echo "  ./devops/manage-statbus.sh generate-config"
    fi
}

check_and_configure_https_only() {
    if detect_http_blocked; then
        echo ""
        echo "This network blocks HTTP traffic, which is used by Docker image builds"
        echo "by default. STATBUS can be configured to use HTTPS-only mirrors instead."
        echo ""
        echo -e "${YELLOW}Note: This may also indicate a temporary network issue.${NC}"
        echo ""
        read -p "Enable HTTPS-only mode for Docker builds? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            configure_https_only
        else
            echo ""
            log "Skipping HTTPS-only configuration"
            echo "If Docker builds fail, you can enable it later by setting"
            echo "APT_USE_HTTPS_ONLY=true in .env.config and running:"
            echo "  ./devops/manage-statbus.sh generate-config"
        fi
    else
        log_success "Network configuration OK (HTTP traffic allowed)"
    fi
}

# =============================================================================
# Deployment Mode Selection
# =============================================================================

select_deployment_mode() {
    log_header "Deployment Mode Selection"
    
    echo "Select deployment mode:"
    echo ""
    echo -e "  ${BOLD}1) standalone${NC} (Recommended for production)"
    echo "     Single-server deployment with automatic HTTPS (Let's Encrypt)"
    echo "     Public domain required, ports 80/443/5432 exposed"
    echo ""
    echo -e "  ${BOLD}2) private${NC}"
    echo "     Behind a host-level reverse proxy (multi-tenant cloud)"
    echo "     Multiple instances on same host with unique ports"
    echo ""
    echo -e "  ${BOLD}3) development${NC}"
    echo "     Local development only, HTTP with self-signed certs"
    echo ""
    
    read -p "Enter choice [1-3] (default: 1): " mode_choice
    mode_choice=${mode_choice:-1}
    
    case $mode_choice in
        1) DEPLOYMENT_MODE="standalone" ;;
        2) DEPLOYMENT_MODE="private" ;;
        3) DEPLOYMENT_MODE="development" ;;
        *) DEPLOYMENT_MODE="standalone" ;;
    esac
    
    log_success "Selected: $DEPLOYMENT_MODE"
}

# =============================================================================
# Standalone Mode Configuration
# =============================================================================

configure_standalone() {
    log_header "Standalone Configuration"
    
    echo "Enter your public domain for this STATBUS installation."
    echo "This domain must point to this server's IP address."
    echo ""
    read -p "Domain (e.g., statbus.example.com): " SITE_DOMAIN
    
    if [[ -z "$SITE_DOMAIN" ]]; then
        log_error "Domain is required for standalone mode"
        exit 1
    fi
    
    echo ""
    echo "TLS Certificate options:"
    echo ""
    echo -e "  ${BOLD}1) Automatic (Let's Encrypt)${NC} - Recommended"
    echo "     Caddy will automatically obtain and renew certificates"
    echo ""
    echo -e "  ${BOLD}2) Custom certificate${NC}"
    echo "     You provide your own .crt and .key files"
    echo ""
    read -p "Enter choice [1-2] (default: 1): " tls_choice
    tls_choice=${tls_choice:-1}
    
    TLS_CUSTOM=false
    if [[ "$tls_choice" == "2" ]]; then
        TLS_CUSTOM=true
        echo ""
        log_warn "After installation, place your certificate files in:"
        echo "  $INSTALL_DIR/caddy/data/custom-certs/"
        echo ""
        log_warn "Then edit .env.config and set:"
        echo "  TLS_CERT_FILE=/data/custom-certs/your-domain.crt"
        echo "  TLS_KEY_FILE=/data/custom-certs/your-domain.key"
        echo ""
        read -p "Press Enter to continue..."
    fi
    
    log_success "Domain: $SITE_DOMAIN"
    log_success "TLS: $(if [[ "$TLS_CUSTOM" == "true" ]]; then echo "Custom certificate"; else echo "Automatic (Let's Encrypt)"; fi)"
}

# =============================================================================
# Setup Configuration Files
# =============================================================================

setup_config() {
    log_header "Configuration Setup"
    
    pushd "$INSTALL_DIR" > /dev/null
    
    # Create .users.yml if it doesn't exist
    if [[ ! -f ".users.yml" ]]; then
        if [[ -f ".users.example" ]]; then
            log "Creating .users.yml from example..."
            cp .users.example .users.yml
            log_warn "Edit .users.yml to add your admin users"
        else
            log_warn ".users.example not found, skipping user file creation"
        fi
    else
        log_success ".users.yml already exists"
    fi
    
    # Check for .env.config - generate if missing
    local env_config=".env.config"
    if [[ ! -f "$env_config" ]]; then
        log "Generating initial configuration..."
        ./devops/manage-statbus.sh generate-config
    else
        log_success ".env.config already exists"
    fi
    
    # Apply deployment mode settings
    if [[ -n "${DEPLOYMENT_MODE:-}" ]]; then
        log "Applying deployment mode: $DEPLOYMENT_MODE"
        
        # Update deployment mode
        sed -i.bak "s|^CADDY_DEPLOYMENT_MODE=.*|CADDY_DEPLOYMENT_MODE=$DEPLOYMENT_MODE|" "$env_config"
        
        if [[ "$DEPLOYMENT_MODE" == "standalone" ]]; then
            # Standalone mode: offset 0, prod code, domain-based URLs
            sed -i.bak "s|^DEPLOYMENT_SLOT_CODE=.*|DEPLOYMENT_SLOT_CODE=prod|" "$env_config"
            sed -i.bak "s|^DEPLOYMENT_SLOT_PORT_OFFSET=.*|DEPLOYMENT_SLOT_PORT_OFFSET=0|" "$env_config"
            sed -i.bak "s|^DEPLOYMENT_SLOT_NAME=.*|DEPLOYMENT_SLOT_NAME=Production|" "$env_config"
            sed -i.bak "s|^SITE_DOMAIN=.*|SITE_DOMAIN=$SITE_DOMAIN|" "$env_config"
            sed -i.bak "s|^STATBUS_URL=.*|STATBUS_URL=https://$SITE_DOMAIN|" "$env_config"
            sed -i.bak "s|^BROWSER_REST_URL=.*|BROWSER_REST_URL=https://$SITE_DOMAIN|" "$env_config"
            sed -i.bak "s|^SERVER_REST_URL=.*|SERVER_REST_URL=http://proxy|" "$env_config"
            sed -i.bak "s|^POSTGRES_APP_DB=.*|POSTGRES_APP_DB=statbus_prod|" "$env_config"
            # Disable debug for production
            sed -i.bak "s|^DEBUG=.*|DEBUG=false|" "$env_config"
            sed -i.bak "s|^NEXT_PUBLIC_DEBUG=.*|NEXT_PUBLIC_DEBUG=false|" "$env_config"
            
            log_success "Configured for standalone mode with domain: $SITE_DOMAIN"
        fi
        
        rm -f "$env_config.bak"
        
        # Regenerate .env with updated config
        log "Regenerating configuration..."
        ./devops/manage-statbus.sh generate-config
    fi
    
    popd > /dev/null
}

# =============================================================================
# Main
# =============================================================================

show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'EOF'
   _____ _        _   ____            
  / ____| |      | | |  _ \           
 | (___ | |_ __ _| |_| |_) |_   _ ___ 
  \___ \| __/ _` | __|  _ <| | | / __|
  ____) | || (_| | |_| |_) | |_| \__ \
 |_____/ \__\__,_|\__|____/ \__,_|___/
                                      
   Installation Script
EOF
    echo -e "${NC}"
    echo "  Install directory: $INSTALL_DIR"
    echo ""
}

show_next_steps() {
    log_header "Installation Complete!"
    
    echo "STATBUS has been installed to: $INSTALL_DIR"
    echo ""
    echo -e "${BOLD}Configuration summary:${NC}"
    echo "  Deployment mode: ${DEPLOYMENT_MODE:-not set}"
    if [[ "${DEPLOYMENT_MODE:-}" == "standalone" ]]; then
        echo "  Domain: ${SITE_DOMAIN:-not set}"
        echo "  Ports: 80 (HTTP), 443 (HTTPS), 5432 (PostgreSQL TLS)"
    fi
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "1. Change to the STATBUS directory:"
    echo -e "   ${CYAN}cd $INSTALL_DIR${NC}"
    echo ""
    echo "2. Edit the users file to add your admin users:"
    echo -e "   ${CYAN}nano .users.yml${NC}"
    echo ""
    if [[ "${DEPLOYMENT_MODE:-}" != "standalone" ]]; then
        echo "3. Edit the deployment configuration (if needed):"
        echo -e "   ${CYAN}nano .env.config${NC}"
        echo ""
        echo "   Key settings to configure:"
        echo "   - DEPLOYMENT_SLOT_NAME: Human-readable name"
        echo "   - DEPLOYMENT_SLOT_CODE: Short code (lowercase, no spaces)"
        echo "   - SITE_DOMAIN: Your domain"
        echo ""
        echo "4. Regenerate configuration after editing:"
        echo -e "   ${CYAN}./devops/manage-statbus.sh generate-config${NC}"
        echo ""
        echo "5. Start all services:"
    else
        echo "3. Start all services:"
    fi
    echo -e "   ${CYAN}./devops/manage-statbus.sh start all${NC}"
    echo ""
    if [[ "${DEPLOYMENT_MODE:-}" != "standalone" ]]; then
        echo "6. Initialize the database (first time only):"
    else
        echo "4. Initialize the database (first time only):"
    fi
    echo -e "   ${CYAN}./devops/manage-statbus.sh create-db${NC}"
    echo ""
    if [[ "${DEPLOYMENT_MODE:-}" != "standalone" ]]; then
        echo "7. Verify deployment:"
    else
        echo "5. Verify deployment:"
    fi
    echo -e "   ${CYAN}docker compose ps${NC}"
    echo ""
    if [[ "${DEPLOYMENT_MODE:-}" == "standalone" ]]; then
        echo "Your STATBUS instance will be available at:"
        echo -e "   ${CYAN}https://${SITE_DOMAIN}${NC}"
        echo ""
    fi
    echo "For detailed instructions, see:"
    echo "  $INSTALL_DIR/doc/DEPLOYMENT.md"
    echo ""
}

main() {
    show_banner
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --dir=*)
                INSTALL_DIR="${arg#*=}"
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dir=PATH    Install directory (default: ~/statbus)"
                echo "  --help, -h    Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    install_crystal
    clone_repository
    build_cli
    select_deployment_mode
    if [[ "$DEPLOYMENT_MODE" == "standalone" ]]; then
        configure_standalone
    fi
    setup_config
    check_and_configure_https_only
    show_next_steps
}

main "$@"
