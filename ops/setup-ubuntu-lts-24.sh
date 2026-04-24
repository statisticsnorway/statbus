#!/bin/bash
#
# setup-ubuntu-lts-24.sh
# Ubuntu 24.04 LTS Server Setup Script
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/ops/setup-ubuntu-lts-24.sh -o harden.sh
#   chmod +x harden.sh
#   sudo ./harden.sh
#
# Non-interactive mode (uses .env values, runs all stages):
#   sudo ./harden.sh --non-interactive
#
# Configuration is stored in ~/.setup-ubuntu.env
#

set -o pipefail

# =============================================================================
# Configuration
# =============================================================================

ENV_FILE="${HOME}/.setup-ubuntu.env"
SCRIPT_VERSION="1.0.0"
NON_INTERACTIVE=false
# Space-separated list of stage numbers to skip (e.g. "0 4"). Honored in both
# interactive and non-interactive mode. Also settable via --skip-stages.
SKIP_STAGES="${SKIP_STAGES:-}"

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

# =============================================================================
# Utility Functions
# =============================================================================

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

verify() {
    local description="$1"
    local command="$2"
    
    if eval "$command" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description"
        return 1
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        return 0  # Default to yes in non-interactive mode
    fi

    local yn_hint="[y/N]"
    [[ "$default" == "y" ]] && yn_hint="[Y/n]"

    while true; do
        read -r -p "$prompt $yn_hint: " answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# stage_skipped <N> — return 0 if stage N appears in SKIP_STAGES.
# Used at the top of each stage so both interactive and non-interactive
# runs can honor a "skip this one" instruction.
stage_skipped() {
    local n="$1"
    # SKIP_STAGES is space-separated; add spaces on both sides to anchor
    # matching so "1" doesn't match "10" etc.
    case " ${SKIP_STAGES} " in
        *" $n "*) return 0 ;;
        *) return 1 ;;
    esac
}

pause() {
    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        read -r -p "Press Enter to continue..."
    fi
}

# =============================================================================
# Environment File Handling
# =============================================================================

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        return 0
    fi
    return 1
}

save_env() {
    cat > "$ENV_FILE" << EOF
# setup-ubuntu-lts-24.sh configuration
# Generated: $(date -Iseconds)

# Email for unattended-upgrades notifications
ADMIN_EMAIL="${ADMIN_EMAIL:-}"

# Space-separated GitHub usernames for SSH key fetching
GITHUB_USERS="${GITHUB_USERS:-}"

# Space-separated extra locale codes without .UTF-8 suffix (e.g., "sq_AL nb_NO")
# The script adds .UTF-8 automatically. C.UTF-8 and en_US.UTF-8 are always included.
EXTRA_LOCALES="${EXTRA_LOCALES:-}"

# Username for the StatBus deployment service account created by Stage 7.
# This is the user operators will ssh as to run ./sb install and operate the
# deployment (distinct from devops, which is the ops/admin user from Stage 6).
SERVICE_USER="${SERVICE_USER:-statbus}"

EOF
    chmod 600 "$ENV_FILE"
}

prompt_env_value() {
    local var_name="$1"
    local description="$2"
    local current_value="${!var_name}"
    local new_value
    
    echo ""
    echo -e "${BOLD}$description${NC}"
    if [[ -n "$current_value" ]]; then
        echo -e "Current value: ${CYAN}$current_value${NC}"
        read -r -p "New value (Enter to keep current): " new_value
        if [[ -n "$new_value" ]]; then
            eval "$var_name=\"$new_value\""
        fi
    else
        read -r -p "Value: " new_value
        eval "$var_name=\"$new_value\""
    fi
}

setup_env() {
    log_header "Configuration Setup"
    
    local env_exists=false
    if load_env; then
        env_exists=true
        log "Found existing configuration at $ENV_FILE"
        echo ""
        echo "Current configuration:"
        echo -e "  ADMIN_EMAIL:   ${CYAN}${ADMIN_EMAIL:-<not set>}${NC}"
        echo -e "  GITHUB_USERS:  ${CYAN}${GITHUB_USERS:-<not set>}${NC}"
        echo -e "  EXTRA_LOCALES: ${CYAN}${EXTRA_LOCALES:-<not set>}${NC}"
        echo ""
        
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log "Using existing configuration (non-interactive mode)"
            return 0
        fi
        
        if ! ask_yes_no "Do you want to modify the configuration?"; then
            return 0
        fi
    else
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log_error "No configuration file found at $ENV_FILE"
            log_error "Non-interactive mode requires an existing .env file"
            log "Create one with the following variables:"
            echo "  ADMIN_EMAIL=\"your@email.com\""
            echo "  GITHUB_USERS=\"username1 username2\""
            echo "  EXTRA_LOCALES=\"sq_AL nb_NO\""
            echo "  SERVICE_USER=\"statbus\"   # optional; default is 'statbus'"
            exit 1
        fi
        log "No configuration found. Let's set up your preferences."
    fi

    prompt_env_value "ADMIN_EMAIL" "Email address for system notifications (unattended-upgrades):"
    prompt_env_value "GITHUB_USERS" "GitHub usernames for SSH key fetching (space-separated):"
    prompt_env_value "EXTRA_LOCALES" "Extra locales to enable without .UTF-8 suffix (e.g., 'sq_AL nb_NO'):"
    SERVICE_USER="${SERVICE_USER:-statbus}"
    prompt_env_value "SERVICE_USER" "Deployment service-account username for Stage 7 (default: statbus):"

    save_env
    log_success "Configuration saved to $ENV_FILE"
}

# =============================================================================
# Stage 0: HTTPS APT Sources
# =============================================================================

stage_https_sources() {
    log_header "Stage 0: HTTPS APT Sources"

    if stage_skipped 0; then
        log_warn "Stage 0 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Switch APT sources from HTTP to HTTPS"
    echo "  - Use mirrors.edge.kernel.org (reliable HTTPS mirror)"
    echo ""
    echo -e "${YELLOW}NOTE: Required if your network blocks HTTP traffic.${NC}"
    echo -e "${YELLOW}      Ubuntu's default mirrors use HTTP for package updates.${NC}"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 0"
        return 0
    fi
    
    local sources_file="/etc/apt/sources.list.d/ubuntu.sources"
    local old_sources="/etc/apt/sources.list"
    
    # Handle both old-style sources.list and new DEB822 format
    if [[ -f "$sources_file" ]]; then
        log "Detected DEB822 format (ubuntu.sources)"
        
        if grep -q "mirrors.edge.kernel.org" "$sources_file"; then
            log "HTTPS mirror already configured"
        else
            log "Backing up original sources..."
            cp "$sources_file" "${sources_file}.bak"
            
            log "Switching to HTTPS mirror..."
            sed -i 's|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' "$sources_file"
        fi
    elif [[ -f "$old_sources" ]]; then
        log "Detected legacy sources.list format"
        
        if grep -q "mirrors.edge.kernel.org" "$old_sources"; then
            log "HTTPS mirror already configured"
        else
            log "Backing up original sources..."
            cp "$old_sources" "${old_sources}.bak"
            
            log "Switching to HTTPS mirror..."
            sed -i 's|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' "$old_sources"
        fi
    else
        log_warn "No standard sources file found"
    fi
    
    log "Updating package lists..."
    apt-get update -qq
    
    # Verification
    echo ""
    log "Verifying Stage 0..."
    verify "HTTPS sources configured" "grep -r 'https://mirrors.edge.kernel.org' /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null | grep -q https"
    verify "APT update succeeds" "apt-get update -qq"
    
    pause
}

# =============================================================================
# Stage 1: Base System Setup
# =============================================================================

stage_base_system() {
    log_header "Stage 1: Base System Setup"

    if stage_skipped 1; then
        log_warn "Stage 1 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install etckeeper for /etc version control"
    echo "  - Configure eternal bash history"
    echo "  - Configure system locales"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 1"
        return 0
    fi
    
    log "Installing etckeeper..."
    apt-get update -qq
    apt-get install -y etckeeper
    
    if [[ -d /etc/.git ]]; then
        log "etckeeper already initialized"
    else
        pushd /etc > /dev/null
        etckeeper init
        etckeeper commit "Initial commit before hardening"
        popd > /dev/null
    fi
    
    log "Configuring eternal bash history..."
    if ! grep -q "HISTFILE=~/.bash_eternal_history" /etc/bash.bashrc; then
        # NB: `<<'EOF'` is a quoted heredoc — the shell writes every byte
        # between here and EOF verbatim, without expansion. So do NOT
        # backslash-escape `$`; the contents below are what bash will read
        # from /etc/bash.bashrc, not a string being assembled in this script.
        cat >> /etc/bash.bashrc <<'EOF'

#### Keep eternal command history for auditing purposes
#### Ref: http://superuser.com/a/664061/103683
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.bash_eternal_history
# Flush history after every command. Guarded with a case-match so re-sourcing
# this file (or a nested login shell) doesn't stack "history -a; history -a;..."
# which previously produced a self-referential expansion and the classic
# `bash: history: -;: invalid option` banner on every prompt draw.
case ":${PROMPT_COMMAND:-}:" in
    *":history -a:"*) ;;
    *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
EOF
    else
        log "Eternal bash history already configured"
    fi
    
    log "Configuring locales..."
    # Always enable these base locales
    sed -i -e 's/# C.UTF-8 UTF-8/C.UTF-8 UTF-8/' /etc/locale.gen
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    
    # Enable extra locales from config
    if [[ -n "$EXTRA_LOCALES" ]]; then
        for locale in $EXTRA_LOCALES; do
            locale_pattern="${locale}.UTF-8 UTF-8"
            if grep -q "# $locale_pattern" /etc/locale.gen; then
                sed -i -e "s/# $locale_pattern/$locale_pattern/" /etc/locale.gen
                log "Enabled locale: $locale"
            elif grep -q "$locale_pattern" /etc/locale.gen; then
                log "Locale already enabled: $locale"
            else
                log_warn "Locale not found in locale.gen: $locale"
            fi
        done
    fi
    
    dpkg-reconfigure --frontend=noninteractive locales
    
    # Set default locale
    cat > /etc/default/locale <<'EOF'
LC_ALL=C.UTF-8
EOF
    
    # Verification
    echo ""
    log "Verifying Stage 1..."
    verify "etckeeper installed" "which etckeeper"
    verify "etckeeper initialized" "test -d /etc/.git"
    verify "Bash history config present" "grep -q 'bash_eternal_history' /etc/bash.bashrc"
    # C.UTF-8 is a built-in locale on Ubuntu 24.04 and does NOT appear in
    # `locale -a` output (which only lists generated locales). Test usability
    # instead: try to use it and catch the "Cannot set" failure mode.
    verify "C.UTF-8 locale available" "LC_ALL=C.UTF-8 locale 2>&1 | grep -qv 'Cannot set'"
    verify "en_US.UTF-8 locale available" "locale -a | grep -q 'en_US.utf8'"
    
    pause
}

# =============================================================================
# Stage 2: SSH Hardening
# =============================================================================

stage_ssh_hardening() {
    log_header "Stage 2: SSH Hardening"

    if stage_skipped 2; then
        log_warn "Stage 2 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Disable root password login (key-only)"
    echo "  - Disable password authentication"
    echo "  - Disable empty passwords"
    echo "  - Disable keyboard-interactive authentication"
    echo ""
    echo -e "${YELLOW}WARNING: Ensure you have console access or SSH keys set up!${NC}"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 2"
        return 0
    fi
    
    log "Configuring SSH..."
    cat > /etc/ssh/sshd_config.d/hardening.conf <<'EOF'
# SSH Hardening Configuration
# Generated by setup-ubuntu-lts-24.sh

PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
AcceptEnv LANG LC_* GIT_*
EOF
    
    log "Testing SSH configuration..."
    if sshd -t; then
        log_success "SSH configuration valid"
        log "Restarting SSH service..."
        systemctl restart ssh || systemctl restart sshd
    else
        log_error "SSH configuration test failed! Rolling back..."
        rm -f /etc/ssh/sshd_config.d/hardening.conf
        return 1
    fi
    
    # Verification
    echo ""
    log "Verifying Stage 2..."
    verify "Hardening config exists" "test -f /etc/ssh/sshd_config.d/hardening.conf"
    verify "SSH config valid" "sshd -t"
    verify "SSH service running" "systemctl is-active ssh || systemctl is-active sshd"
    verify "Root password login disabled" "grep -q 'PermitRootLogin prohibit-password' /etc/ssh/sshd_config.d/hardening.conf"
    verify "Password auth disabled" "grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config.d/hardening.conf"
    
    pause
}

# =============================================================================
# Stage 3: Automatic Updates
# =============================================================================

stage_auto_updates() {
    log_header "Stage 3: Automatic Updates"

    if stage_skipped 3; then
        log_warn "Stage 3 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install unattended-upgrades"
    echo "  - Configure automatic security updates"
    echo "  - Set up nightly update schedule (01:00 + random delay)"
    echo "  - Configure reboot time if needed (03:00 + random delay)"
    echo "  - Set notification email: ${ADMIN_EMAIL:-<not configured>}"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 3"
        return 0
    fi
    
    log "Installing unattended-upgrades..."
    apt-get install -y unattended-upgrades
    
    log "Configuring apt-daily timers..."
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    
    # Use configured email or leave empty
    local email_config=""
    if [[ -n "$ADMIN_EMAIL" ]]; then
        email_config="Unattended-Upgrade::Mail \"$ADMIN_EMAIL\";"
    else
        email_config="// Unattended-Upgrade::Mail \"root\";"
    fi
    
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
// Unattended-Upgrade configuration
// Generated by setup-ubuntu-lts-24.sh

Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
    "\${distro_id}:\${distro_codename}-updates";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::DevRelease "auto";
$email_config
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:15";
EOF
    
    log "Configuring update schedule..."
    mkdir -p /etc/systemd/system/apt-daily.timer.d
    cat > /etc/systemd/system/apt-daily.timer.d/override.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 01:00
RandomizedDelaySec=1h
EOF
    
    mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
    cat > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:00
RandomizedDelaySec=40m
EOF
    
    systemctl daemon-reload
    
    # Verification
    echo ""
    log "Verifying Stage 3..."
    verify "unattended-upgrades installed" "dpkg -l | grep -q unattended-upgrades"
    verify "Auto-upgrades config exists" "test -f /etc/apt/apt.conf.d/20auto-upgrades"
    verify "Unattended-upgrades config exists" "test -f /etc/apt/apt.conf.d/50unattended-upgrades"
    verify "apt-daily timer override exists" "test -f /etc/systemd/system/apt-daily.timer.d/override.conf"
    verify "apt-daily-upgrade timer override exists" "test -f /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf"
    
    pause
}

# =============================================================================
# Stage 4: Security Tools (CrowdSec + UFW)
# =============================================================================

stage_security_tools() {
    log_header "Stage 4: Security Tools (CrowdSec + UFW)"

    if stage_skipped 4; then
        log_warn "Stage 4 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install CrowdSec intrusion detection"
    echo "  - Install CrowdSec firewall bouncer (nftables)"
    echo "  - Install SSH log parsers"
    echo "  - Configure UFW firewall"
    echo "  - Allow SSH, HTTP, HTTPS, PostgreSQL through firewall"
    echo ""
    echo -e "${YELLOW}NOTE: Skip this stage if your server is on a private network${NC}"
    echo -e "${YELLOW}      with its own firewall/security infrastructure.${NC}"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 4"
        return 0
    fi
    
    log "Adding CrowdSec repository..."
    curl -s https://install.crowdsec.net | sudo bash
    
    log "Installing CrowdSec..."
    apt-get install -y crowdsec crowdsec-firewall-bouncer-nftables
    
    log "Installing CrowdSec collections..."
    # Wait for CrowdSec config to be fully written before running cscli
    for i in $(seq 1 10); do
        [ -f /etc/crowdsec/config.yaml ] && break
        sleep 1
    done
    cscli collections install crowdsecurity/sshd

    log "Reloading CrowdSec..."
    systemctl reload crowdsec
    
    log "Configuring UFW..."
    apt-get install -y ufw
    ufw allow OpenSSH
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 5432/tcp comment 'PostgreSQL'
    
    # Enable UFW non-interactively
    echo "y" | ufw enable
    
    # Verification
    echo ""
    log "Verifying Stage 4..."
    verify "CrowdSec installed" "which crowdsec"
    verify "CrowdSec running" "systemctl is-active crowdsec"
    # The nftables bouncer installs as `crowdsec-firewall-bouncer-nftables`. Anchor
    # to the `ii` install state prefix so we don't false-positive on config-kept
    # entries (`rc`), and include either the plain or -nftables variant.
    verify "Firewall bouncer installed" "dpkg -l | grep -qE '^ii\s+crowdsec-firewall-bouncer(-nftables)?\s'"
    verify "SSHD collection installed" "cscli collections list | grep -q sshd"
    verify "UFW active" "ufw status | grep -q 'Status: active'"
    verify "SSH allowed in UFW" "ufw status | grep -q 'OpenSSH'"
    verify "HTTP allowed in UFW" "ufw status | grep -q '80/tcp'"
    verify "HTTPS allowed in UFW" "ufw status | grep -q '443/tcp'"
    verify "PostgreSQL allowed in UFW" "ufw status | grep -q '5432/tcp'"
    
    pause
}

# =============================================================================
# Stage 5: Core Tools & System Tuning
# =============================================================================

stage_core_tools() {
    log_header "Stage 5: Core Tools & System Tuning"

    if stage_skipped 5; then
        log_warn "Stage 5 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install tools: neovim, htop, net-tools, jnettop, git, acl, ripgrep, aptitude"
    echo "  - Set neovim as default editor"
    echo "  - Configure memory/swap settings for server workloads"
    echo "  - Install Docker CE with compose plugin"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 5"
        return 0
    fi
    
    log "Installing core tools..."
    apt-get install -y neovim htop net-tools jnettop git acl ripgrep aptitude
    
    log "Configuring neovim..."
    if [[ -f /etc/vim/vimrc ]] && ! grep -q "colorscheme elflord" /etc/vim/vimrc; then
        echo "colorscheme elflord" >> /etc/vim/vimrc
    fi
    update-alternatives --set editor /usr/bin/nvim 2>/dev/null || true
    
    log "Configuring system memory settings..."
    cat > /etc/sysctl.d/20-server-tuning.conf <<'EOF'
# Server Memory Tuning
# Generated by setup-ubuntu-lts-24.sh

# Limit swapping - prefer RAM for server workloads
# 0 prevents swapping altogether, 1 allows minimal swapping for emergencies
vm.swappiness=1

# Hugepages for PostgreSQL (disabled by default, enable and tune as needed)
vm.nr_hugepages=0

# Don't overcommit memory (disabled - .NET and Java need this)
# vm.overcommit_memory=2
# vm.overcommit_ratio=100
vm.overcommit_memory=0

# Reduce unpredictable background work
# dirty_background_bytes: 64 MB
vm.dirty_background_bytes=67108864
# dirty_bytes: 512 MB
vm.dirty_bytes=536870912
EOF
    
    sysctl --system > /dev/null
    
    log "Installing Docker..."
    apt-get install -y ca-certificates curl gnupg
    
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list
    fi
    
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Verification
    echo ""
    log "Verifying Stage 5..."
    verify "neovim installed" "which nvim"
    verify "htop installed" "which htop"
    verify "ripgrep installed" "which rg"
    verify "git installed" "which git"
    verify "System tuning applied" "test -f /etc/sysctl.d/20-server-tuning.conf"
    verify "Docker installed" "which docker"
    verify "Docker running" "systemctl is-active docker"
    verify "Docker Compose installed" "docker compose version"
    
    pause
}

# =============================================================================
# Stage 6: User Setup & Developer Tools
# =============================================================================

stage_user_setup() {
    log_header "Stage 6: User Setup & Developer Tools"

    if stage_skipped 6; then
        log_warn "Stage 6 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Create 'devops' user with passwordless sudo"
    echo "  - Fetch SSH keys from GitHub: ${GITHUB_USERS:-<not configured>}"
    echo "  - Generate ed25519 SSH keypair for devops"
    echo "  - Install Homebrew (owned by devops)"
    echo "  - Install: helix, bottom, zellij"
    echo "  - Configure zellij auto-attach on SSH login"
    echo ""
    
    if [[ -z "$GITHUB_USERS" ]]; then
        log_warn "No GitHub users configured - SSH keys won't be fetched"
    fi
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 6"
        return 0
    fi
    
    log "Creating devops user..."
    if ! id devops &>/dev/null; then
        useradd -r -m -s /bin/bash devops
    else
        log "User devops already exists"
    fi
    
    log "Configuring passwordless sudo..."
    echo "devops ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devops
    chmod 440 /etc/sudoers.d/devops
    
    log "Setting up SSH for devops..."
    sudo -i -u devops bash <<DEVOPS_SETUP
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Fetch SSH keys from GitHub
GITHUB_USERS="$GITHUB_USERS"
for user in \$GITHUB_USERS; do
    echo "Fetching keys for GitHub user: \$user"
    keys=\$(curl -sL "https://github.com/\$user.keys" 2>/dev/null)
    if [[ -n "\$keys" ]]; then
        echo "\$keys" | while read -r key; do
            if [[ -n "\$key" ]]; then
                # Add comment with source
                echo "\$key # https://github.com/\$user.keys" >> ~/.ssh/authorized_keys
            fi
        done
    else
        echo "Warning: No keys found for \$user"
    fi
done

# Remove duplicates while preserving order
if [[ -f ~/.ssh/authorized_keys ]]; then
    awk '!seen[\$0]++' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp
    mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys
fi

# Generate SSH keypair if not exists
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "devops@\$(hostname --fqdn)"
fi

chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true
chmod 600 ~/.ssh/id_ed25519 2>/dev/null || true
chmod 644 ~/.ssh/id_ed25519.pub 2>/dev/null || true
DEVOPS_SETUP
    
    chown -R devops:devops /home/devops/.ssh

    # Grant devops Docker API access. The docker-ce package from Stage 5 creates
    # the `docker` group but does not populate it — an easy thing to miss, and
    # without this membership `docker ps` as devops fails with "permission denied
    # on /var/run/docker.sock", which defeats the whole "log in as devops and
    # operate the box" path that the StatBus docs prescribe.
    if getent group docker >/dev/null; then
        log "Adding devops to docker group..."
        usermod -aG docker devops
    else
        log_warn "docker group missing (Stage 5 may have been skipped) — not adding devops to it"
    fi

    log "Installing Homebrew dependencies..."
    apt-get install -y build-essential curl file git procps
    
    log "Installing Homebrew..."
    if [[ ! -d /home/linuxbrew/.linuxbrew ]]; then
        mkdir -p /home/linuxbrew/.linuxbrew
        chown -R devops:devops /home/linuxbrew/.linuxbrew
        
        # Install Homebrew as devops user
        sudo -u devops bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    else
        log "Homebrew already installed"
    fi
    
    # Set ownership and permissions
    chown -R devops:devops /home/linuxbrew/.linuxbrew
    chmod -R g+rwx /home/linuxbrew/.linuxbrew
    
    # Set up ACLs for devops
    setfacl -R -m u:devops:rwx /home/linuxbrew/.linuxbrew 2>/dev/null || true
    setfacl -R -d -m u:devops:rwx /home/linuxbrew/.linuxbrew 2>/dev/null || true
    
    log "Adding Homebrew to global PATH..."
    cat > /etc/profile.d/linuxbrew.sh <<'EOF'
# Add Homebrew to the PATH for all users
if [ -d "/home/linuxbrew/.linuxbrew/bin" ]; then
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

if [ -d "/home/linuxbrew/.linuxbrew/sbin" ]; then
    export PATH="/home/linuxbrew/.linuxbrew/sbin:$PATH"
fi

# Load Homebrew environment (bash only — brew shellenv uses bash-specific syntax)
if [ -n "$BASH_VERSION" ] && [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Enable bash completion for Homebrew packages (bash only)
if [ -n "$BASH_VERSION" ] && [ -d /home/linuxbrew/.linuxbrew/etc/bash_completion.d ]; then
    for bcfile in /home/linuxbrew/.linuxbrew/etc/bash_completion.d/*; do
        [ -r "$bcfile" ] && . "$bcfile"
    done
fi
EOF
    chmod +x /etc/profile.d/linuxbrew.sh
    
    # Mark linuxbrew as safe for git
    git config --system --add safe.directory /home/linuxbrew/.linuxbrew/Homebrew 2>/dev/null || true
    
    log "Installing developer tools via Homebrew..."
    sudo -u devops bash -c 'cd /tmp && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew install helix bottom zellij' || {
        log "Optional developer tools (helix/bottom/zellij) not available for this architecture — skipping"
    }
    
    log "Configuring zellij auto-attach..."
    cat > /etc/profile.d/zellij.sh <<'EOF'
# Automatically reattach to an existing Zellij session or create a new one.
if command -v zellij &> /dev/null && [ -z "$ZELLIJ_SESSION_NAME" ] && [ -n "$PS1" ]; then
    if zellij list-sessions 2>/dev/null | grep -q "active"; then
        exec zellij attach
    else
        exec zellij
    fi
fi
EOF
    chmod +x /etc/profile.d/zellij.sh
    
    # Verification
    echo ""
    log "Verifying Stage 6..."
    verify "devops user exists" "id devops"
    verify "devops has passwordless sudo" "test -f /etc/sudoers.d/devops"
    verify "devops SSH directory exists" "test -d /home/devops/.ssh"
    if getent group docker >/dev/null; then
        verify "devops is in docker group" "id -nG devops | tr ' ' '\n' | grep -qx docker"
    fi
    verify "Homebrew installed" "test -x /home/linuxbrew/.linuxbrew/bin/brew"
    verify "helix installed" "test -x /home/linuxbrew/.linuxbrew/bin/hx"
    verify "bottom installed" "test -x /home/linuxbrew/.linuxbrew/bin/btm"
    verify "zellij installed" "test -x /home/linuxbrew/.linuxbrew/bin/zellij"
    verify "zellij auto-attach configured" "test -f /etc/profile.d/zellij.sh"
    
    if [[ -n "$GITHUB_USERS" ]]; then
        verify "SSH authorized_keys populated" "test -s /home/devops/.ssh/authorized_keys"
    fi

    pause
}

# =============================================================================
# Stage 7: StatBus Service Account
# =============================================================================
#
# Creates the Linux user that StatBus will be installed under and operated as.
# Separate from devops (Stage 6) on purpose:
#   - devops is the ops/admin user. It has passwordless sudo and is how you
#     do host-level maintenance (journalctl, apt, systemctl, etc.).
#   - SERVICE_USER (default: statbus) owns the ~/statbus/ install tree and
#     runs the docker compose stack. It has docker group membership but no
#     sudo. It's what install.sh expects the invoking user to be (install.sh
#     clones into $HOME and does NOT create a user).
#
# Without this stage, operators following our published procedure hit a
# paper cut: ssh'ing in as the default cloud-image user and running
# install.sh lands the StatBus install in the wrong home (e.g. /home/ubuntu
# or /home/devops). We want /home/<SERVICE_USER>/statbus/ and nothing else.

stage_service_account() {
    log_header "Stage 7: StatBus Service Account"

    if stage_skipped 7; then
        log_warn "Stage 7 skipped via SKIP_STAGES"
        return 0
    fi

    local user="${SERVICE_USER:-statbus}"

    echo "This stage will:"
    echo "  - Create Linux user '$user' with /home/$user as home"
    echo "  - Add '$user' to the docker group"
    echo "  - Populate ~$user/.ssh/authorized_keys from GitHub: ${GITHUB_USERS:-<not configured>}"
    echo "  - Enable systemd linger so user units survive logout"
    echo ""
    echo "  Operators will SSH as '$user' to install/operate StatBus."
    echo ""

    if [[ -z "$GITHUB_USERS" ]]; then
        log_warn "No GitHub users configured — SSH keys won't be fetched and"
        log_warn "nobody will be able to SSH in as '$user' until you add keys manually."
    fi

    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 7"
        return 0
    fi

    log "Creating service-account user '$user'..."
    if id "$user" &>/dev/null; then
        log "User '$user' already exists — reusing"
    else
        useradd -m -s /bin/bash -c "StatBus service account" "$user"
    fi

    if getent group docker >/dev/null; then
        log "Adding '$user' to docker group..."
        usermod -aG docker "$user"
    else
        log_warn "docker group missing (Stage 5 may have been skipped) — not adding '$user' to it"
    fi

    log "Populating SSH keys for '$user'..."
    sudo -i -u "$user" bash <<SETUP
mkdir -p ~/.ssh
chmod 700 ~/.ssh
: > ~/.ssh/authorized_keys.new
for gh_user in $GITHUB_USERS; do
    echo "Fetching keys for GitHub user: \$gh_user"
    keys=\$(curl -sL "https://github.com/\$gh_user.keys" 2>/dev/null || true)
    if [[ -n "\$keys" ]]; then
        echo "\$keys" | while read -r key; do
            [[ -z "\$key" ]] && continue
            echo "\$key # https://github.com/\$gh_user.keys" >> ~/.ssh/authorized_keys.new
        done
    else
        echo "Warning: no keys returned for \$gh_user"
    fi
done
# Merge new keys with any pre-existing ones, deduplicate.
if [[ -s ~/.ssh/authorized_keys ]]; then
    cat ~/.ssh/authorized_keys >> ~/.ssh/authorized_keys.new
fi
awk '!seen[\$0]++' ~/.ssh/authorized_keys.new > ~/.ssh/authorized_keys
rm -f ~/.ssh/authorized_keys.new
chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true
SETUP
    chown -R "$user:$user" "/home/$user/.ssh"

    log "Enabling systemd --user linger for '$user' (so systemctl --user services persist)..."
    loginctl enable-linger "$user"

    # Verification
    echo ""
    log "Verifying Stage 7..."
    verify "$user user exists" "id $user"
    if getent group docker >/dev/null; then
        verify "$user is in docker group" "id -nG $user | tr ' ' '\n' | grep -qx docker"
    fi
    verify "$user .ssh dir exists with correct mode" "test -d /home/$user/.ssh"
    if [[ -n "$GITHUB_USERS" ]]; then
        verify "$user authorized_keys populated" "test -s /home/$user/.ssh/authorized_keys"
    fi
    verify "$user linger enabled" "loginctl show-user $user -p Linger 2>/dev/null | grep -q 'Linger=yes'"

    pause
}

# =============================================================================
# Main
# =============================================================================

show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'EOF'
  _   _               _             
 | | | | __ _ _ __ __| | ___ _ __   
 | |_| |/ _` | '__/ _` |/ _ \ '_ \  
 |  _  | (_| | | | (_| |  __/ | | | 
 |_| |_|\__,_|_|  \__,_|\___|_| |_| 
                                    
  Ubuntu 24.04 LTS Server Setup Script
EOF
    echo -e "${NC}"
    echo "  Version: $SCRIPT_VERSION"
    echo "  Config:  $ENV_FILE"
    echo ""
}

check_prerequisites() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_warn "This script is designed for Ubuntu, detected: $ID"
            if ! ask_yes_no "Continue anyway?"; then
                exit 1
            fi
        fi
        if [[ "$VERSION_ID" != "24.04" ]]; then
            log_warn "This script is designed for Ubuntu 24.04, detected: $VERSION_ID"
            if ! ask_yes_no "Continue anyway?"; then
                exit 1
            fi
        fi
    fi
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --skip-stages)
                if [[ -z "${2:-}" ]]; then
                    log_error "--skip-stages requires an argument (e.g. --skip-stages \"0 4\")"
                    exit 1
                fi
                SKIP_STAGES="$2"
                shift 2
                ;;
            --skip-stages=*)
                SKIP_STAGES="${1#*=}"
                shift
                ;;
            --help|-h)
                show_banner
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --non-interactive          Run all stages without prompting (requires .env file)"
                echo "  --skip-stages \"N [N ...]\"  Skip the given stages (space-separated numbers)."
                echo "                              Also settable via SKIP_STAGES env var."
                echo "  --help, -h                 Show this help message"
                echo ""
                echo "Stages:"
                echo "  0  HTTPS APT Sources (optional)"
                echo "  1  Base System (etckeeper, bash history, locales)"
                echo "  2  SSH Hardening"
                echo "  3  Automatic Updates"
                echo "  4  Security Tools (CrowdSec + UFW, optional)"
                echo "  5  Core Tools (docker, neovim, htop, ...)"
                echo "  6  User Setup (devops user + Homebrew developer tools)"
                echo "  7  StatBus Service Account (statbus user)"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    show_banner
    check_prerequisites
    setup_env

    log_header "Starting Setup Process"

    if [[ -n "$SKIP_STAGES" ]]; then
        log "SKIP_STAGES=\"$SKIP_STAGES\" — those stages will be short-circuited"
    fi
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log "Running in non-interactive mode — all non-skipped stages will be executed"
    else
        echo "You will be prompted before each non-skipped stage."
        echo "Answer 'y' to run a stage, 'n' to skip it."
    fi
    echo ""

    # Run stages
    stage_https_sources
    stage_base_system
    stage_ssh_hardening
    stage_auto_updates
    stage_security_tools
    stage_core_tools
    stage_user_setup
    stage_service_account

    log_header "Setup Complete!"

    echo "Summary of configuration:"
    echo "  - SSH hardened (key-only authentication)"
    echo "  - Automatic security updates enabled"
    echo "  - CrowdSec intrusion detection active"
    echo "  - UFW firewall enabled"
    echo "  - Docker installed"
    echo "  - devops user created (ops/admin)"
    echo "  - Homebrew + developer tools installed"
    echo "  - ${SERVICE_USER:-statbus} service account created (for StatBus install)"
    echo ""
    echo "Recommended next steps:"
    echo "  1. Log in as '${SERVICE_USER:-statbus}' and verify SSH key access"
    echo "  2. Run the StatBus installer as that user:"
    echo "       ssh ${SERVICE_USER:-statbus}@\$(hostname --fqdn)"
    echo "       curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease"
    echo "  3. (ops) Log in as 'devops' for host administration tasks"
    echo "  4. Review CrowdSec with: cscli metrics"
    echo "  5. Check firewall status with: ufw status"
    echo ""

    if [[ -f /var/run/reboot-required ]]; then
        log_warn "A reboot is required to complete the setup"
    fi
}

main "$@"
