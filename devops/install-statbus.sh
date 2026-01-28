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
#   curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/main/devops/install-statbus.sh -o install-statbus.sh
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
        echo "  curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/main/devops/harden-ubuntu-lts-24.sh -o harden.sh"
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
    
    # Check for .env.config
    if [[ ! -f ".env.config" ]]; then
        log "Generating initial configuration..."
        ./devops/manage-statbus.sh generate-config
        log_warn "Edit .env.config to configure your deployment"
    else
        log_success ".env.config already exists"
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
    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "1. Change to the STATBUS directory:"
    echo -e "   ${CYAN}cd $INSTALL_DIR${NC}"
    echo ""
    echo "2. Edit the users file to add your admin users:"
    echo -e "   ${CYAN}nano .users.yml${NC}"
    echo ""
    echo "3. Edit the deployment configuration:"
    echo -e "   ${CYAN}nano .env.config${NC}"
    echo ""
    echo "   Key settings to configure:"
    echo "   - DEPLOYMENT_SLOT_NAME: Human-readable name"
    echo "   - DEPLOYMENT_SLOT_CODE: Short code (lowercase, no spaces)"
    echo "   - CADDY_DEPLOYMENT_MODE: standalone (or private/development)"
    echo "   - SITE_DOMAIN: Your public domain"
    echo ""
    echo "4. Regenerate configuration after editing:"
    echo -e "   ${CYAN}./devops/manage-statbus.sh generate-config${NC}"
    echo ""
    echo "5. Start all services:"
    echo -e "   ${CYAN}./devops/manage-statbus.sh start all${NC}"
    echo ""
    echo "6. Initialize the database (first time only):"
    echo -e "   ${CYAN}./devops/manage-statbus.sh create-db${NC}"
    echo ""
    echo "7. Verify deployment:"
    echo -e "   ${CYAN}docker compose ps${NC}"
    echo ""
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
    setup_config
    show_next_steps
}

main "$@"
