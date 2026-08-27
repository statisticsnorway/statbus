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
# STATBUS-207: verify() failures, collected across every stage. main() runs
# every stage to completion regardless (maximal diagnostics — the VM is
# torn down after this run, so a fail-fast here would hide whatever came
# after the first ✗) and exits non-zero at the very end if this is
# non-empty, so a real regression finally reaches the harness's exit code
# instead of vanishing into stage output nobody's automation checks.
FAILED_VERIFICATIONS=()

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
        FAILED_VERIFICATIONS+=("$description")
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
# Centralized SSH-key Installer
# =============================================================================
#
# populate_authorized_keys — single source of truth for seeding a system
# user's ~/.ssh/authorized_keys from GitHub.
#
# Behaviour contract:
#   * ED25519-only filter. RSA keys are dropped at the source — keeping
#     them just because GitHub exposes them is dead weight on modern
#     OpenSSH (and they were the symptom of a previous "8KB MaxAuthSize
#     exceeded" lockout).
#   * Both source forms are supported, auto-detected by presence of `/`:
#       - `<user>`        → https://github.com/<user>.keys
#       - `<org>/<repo>`  → https://github.com/<org>/<repo>.keys
#     The repo form returns the repo's deploy keys; this is how CI like
#     deploy-to-* gets ssh access without a personal key being in play.
#   * Idempotent: existing keys (added by hand, by a prior run, or by
#     another mechanism) are preserved. Re-runs converge — no duplicates.
#   * Each key is annotated with `# <source URL>` so an operator looking
#     at authorized_keys later can tell which line came from where.
#
# Usage (must be run as root; switches to target user via sudo internally):
#   populate_authorized_keys <target_user> "<users_list>" "<deploy_keys_list>"
#
# Both list args are whitespace-separated. Empty strings are valid.
populate_authorized_keys() {
    local target_user="$1"
    local users_list="$2"
    local deploy_keys_list="$3"

    local home_dir
    home_dir="$(getent passwd "$target_user" | cut -d: -f6)"
    if [[ -z "$home_dir" ]]; then
        log_error "populate_authorized_keys: user '$target_user' has no home directory"
        return 1
    fi

    local ssh_dir="$home_dir/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    local stage_file="$ssh_dir/.authorized_keys.stage.$$"

    # Ensure .ssh dir exists with correct ownership/mode.
    mkdir -p "$ssh_dir"
    chown "$target_user:$target_user" "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Build a fresh staging file with all fetched keys, then merge with any
    # pre-existing authorized_keys before deduplicating. This preserves
    # operator-added entries that aren't tracked here.
    : > "$stage_file"

    local source url keys key
    for source in $users_list; do
        if [[ "$source" == */* ]]; then
            log_warn "populate_authorized_keys: '$source' looks like a deploy-key (org/repo) but appears in users list — moving it to GITHUB_DEPLOY_KEYS is recommended"
        fi
        url="https://github.com/${source}.keys"
        log "Fetching ED25519 keys from $url"
        keys="$(curl -sL --fail "$url" 2>/dev/null || true)"
        if [[ -z "$keys" ]]; then
            log_warn "No keys returned from $url"
            continue
        fi
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            # Match ssh-ed25519 only — anchor to start, allow optional
            # `<options> ` prefix and require a space after the type tag
            # so `ssh-ed25519abcd` (would not occur, but defensively) fails.
            if [[ "$key" =~ (^|[[:space:]])ssh-ed25519[[:space:]] ]]; then
                printf '%s # %s\n' "$key" "$url" >> "$stage_file"
            fi
        done <<< "$keys"
    done

    for source in $deploy_keys_list; do
        if [[ "$source" != */* ]]; then
            log_warn "populate_authorized_keys: '$source' has no '/' but appears in deploy-keys list — expected <org>/<repo> form"
        fi
        url="https://github.com/${source}.keys"
        log "Fetching ED25519 deploy keys from $url"
        keys="$(curl -sL --fail "$url" 2>/dev/null || true)"
        if [[ -z "$keys" ]]; then
            log_warn "No deploy keys returned from $url (repo public + deploy-keys readable?)"
            continue
        fi
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            if [[ "$key" =~ (^|[[:space:]])ssh-ed25519[[:space:]] ]]; then
                printf '%s # %s\n' "$key" "$url" >> "$stage_file"
            fi
        done <<< "$keys"
    done

    # Merge in any pre-existing authorized_keys (operator-added entries).
    if [[ -s "$auth_keys" ]]; then
        cat "$auth_keys" >> "$stage_file"
    fi

    # Dedupe by key body (algo + base64), preserving order. This keeps the
    # first source-comment that introduced each key. Lines that aren't a
    # recognisable key (blank or `# comment-only`) are filtered.
    awk '
        {
            # Skip blank lines and comment-only lines.
            if ($0 ~ /^[[:space:]]*$/) next
            stripped = $0
            sub(/^[[:space:]]*/, "", stripped)
            if (substr(stripped, 1, 1) == "#") next
            # Identify the key body. SSH authorized_keys allows optional
            # `<options>` before the algo+base64 pair. Robust extract: scan
            # tokens until we find one whose tag starts with `ssh-` or
            # `ecdsa-` etc; the next token is the base64 body.
            n = split($0, t, /[[:space:]]+/)
            algo_idx = 0
            for (i = 1; i <= n; i++) {
                if (t[i] ~ /^(ssh-|ecdsa-|sk-)/) { algo_idx = i; break }
            }
            if (algo_idx == 0 || algo_idx + 1 > n) next
            keybody = t[algo_idx] " " t[algo_idx + 1]
            if (!seen[keybody]++) print
        }
    ' "$stage_file" > "$auth_keys"
    rm -f "$stage_file"

    chown "$target_user:$target_user" "$auth_keys"
    chmod 600 "$auth_keys"

    log_success "populate_authorized_keys: $(wc -l < "$auth_keys") key(s) written to $auth_keys"
}

# =============================================================================
# Per-Stage Input Declarations (STATBUS-259)
# =============================================================================
#
# Each stage declares which .env keys it actually reads, so the preamble can
# require only the UNION over the NON-SKIPPED stages — never inferred from
# shared logic, never assumed from what some OTHER stage needs. This is what
# lets a stage-8-only run (--skip-stages "0 1 2 3 4 5 6 7") proceed without
# /root/.setup-ubuntu.env: Stage 8 needs SSHDOERS_REF/SSHDOERS_HOST (declared
# below, validated inside the stage itself) and no .env variable at all, so
# the union over {8} is empty.
#
# CONSERVATIVE DEFAULT, load-bearing: a stage NUMBER ABSENT from this map
# requires EVERYTHING (ALL_ENV_VARS below). A newly added stage that forgets
# to declare itself therefore fails TOO STRICT — it demands the full legacy
# set, exactly today's behavior — never too permissive: it can never silently
# skip a variable it actually needed. Relaxing a stage's requirement (to a
# narrower list, or to none) is opt-in and explicit: add its number as a key.
#
# Presence, not truthiness, is what selects the conservative default: an
# empty value for a PRESENT key ("declared, needs nothing") must read
# differently from an ABSENT key ("undeclared, needs everything"). Tested
# with `${STAGE_ENV_REQUIREMENTS[$n]+_}`, never with `-z`/`-n` on the value.
declare -A STAGE_ENV_REQUIREMENTS=(
    [0]=""                                                # HTTPS APT Sources
    [1]="EXTRA_LOCALES"                                   # Base System
    [2]=""                                                # SSH Hardening
    [3]="ADMIN_EMAIL"                                     # Automatic Updates
    [4]=""                                                # Security Tools
    [5]=""                                                # Core Tools
    [6]="GITHUB_USERS GITHUB_DEPLOY_KEYS"                 # User Setup
    [7]="GITHUB_USERS GITHUB_DEPLOY_KEYS SERVICE_USER"    # StatBus Service Account
    [8]=""                                                # CI Command Allowlist —
                                                           # SSHDOERS_REF/SSHDOERS_HOST
                                                           # only; validated inside the
                                                           # stage, not .env variables.
)

# ALL_ENV_VARS — the full legacy set, applied as the conservative default for
# any stage number absent from STAGE_ENV_REQUIREMENTS above.
ALL_ENV_VARS="ADMIN_EMAIL GITHUB_USERS GITHUB_DEPLOY_KEYS EXTRA_LOCALES SERVICE_USER"

# required_env_vars — prints the UNION of declared requirements over the
# stages that are NOT skipped (SKIP_STAGES / stage_skipped), one per line,
# sorted and de-duplicated. A stage contributes NOTHING once skipped,
# regardless of what it would otherwise require.
required_env_vars() {
    local -A seen=()
    local n var
    for n in 0 1 2 3 4 5 6 7 8; do
        stage_skipped "$n" && continue
        if [[ "${STAGE_ENV_REQUIREMENTS[$n]+_}" != "_" ]]; then
            # Undeclared stage number: conservative default, require everything.
            for var in $ALL_ENV_VARS; do seen["$var"]=1; done
            continue
        fi
        for var in ${STAGE_ENV_REQUIREMENTS[$n]}; do
            [[ -n "$var" ]] && seen["$var"]=1
        done
    done
    if [[ ${#seen[@]} -gt 0 ]]; then
        printf '%s\n' "${!seen[@]}" | sort
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

# Space-separated GitHub repo deploy-key sources in <org>/<repo> form,
# fetched from https://github.com/<org>/<repo>.keys. Used to authorize
# CI deploy access (the deploy-to-rune-no GitHub Actions workflow needs
# its repo deploy key in ~statbus/.ssh/authorized_keys to ssh in).
# SSB-operated default is "statisticsnorway/statbus".
GITHUB_DEPLOY_KEYS="${GITHUB_DEPLOY_KEYS:-statisticsnorway/statbus}"

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

    # STATBUS-259: only require $ENV_FILE at all if some NON-SKIPPED stage in
    # THIS run actually declares a need for it (required_env_vars above) —
    # never inferred from what a full run would need. A stage-8-only run
    # (--skip-stages "0 1 2 3 4 5 6 7") declares nothing, so $required is
    # empty and this function does not demand the file.
    local required
    required="$(required_env_vars)"

    local env_exists=false
    if load_env; then
        env_exists=true
        log "Found existing configuration at $ENV_FILE"
        echo ""
        echo "Current configuration:"
        echo -e "  ADMIN_EMAIL:        ${CYAN}${ADMIN_EMAIL:-<not set>}${NC}"
        echo -e "  GITHUB_USERS:       ${CYAN}${GITHUB_USERS:-<not set>}${NC}"
        echo -e "  GITHUB_DEPLOY_KEYS: ${CYAN}${GITHUB_DEPLOY_KEYS:-<not set>}${NC}"
        echo -e "  EXTRA_LOCALES:      ${CYAN}${EXTRA_LOCALES:-<not set>}${NC}"
        echo ""
        
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log "Using existing configuration (non-interactive mode)"
            return 0
        fi
        
        if ! ask_yes_no "Do you want to modify the configuration?"; then
            return 0
        fi
    else
        if [[ -z "$required" ]]; then
            # STATBUS-259: no non-skipped stage in this run needs $ENV_FILE —
            # e.g. a stage-8-only run. Proceed without it.
            log "No non-skipped stage in this run requires $ENV_FILE — skipping configuration setup"
            return 0
        fi
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log_error "No configuration file found at $ENV_FILE"
            log_error "Non-interactive mode requires it for this run's stages, which need:"
            local var
            for var in $required; do
                case "$var" in
                    ADMIN_EMAIL)        echo "  ADMIN_EMAIL=\"your@email.com\"" ;;
                    GITHUB_USERS)       echo "  GITHUB_USERS=\"username1 username2\"" ;;
                    GITHUB_DEPLOY_KEYS) echo "  GITHUB_DEPLOY_KEYS=\"statisticsnorway/statbus\"   # optional; CI deploy keys" ;;
                    EXTRA_LOCALES)      echo "  EXTRA_LOCALES=\"sq_AL nb_NO\"" ;;
                    SERVICE_USER)       echo "  SERVICE_USER=\"statbus\"   # optional; default is 'statbus'" ;;
                esac
            done
            exit 1
        fi
        log "No configuration found. Let's set up your preferences."
    fi

    prompt_env_value "ADMIN_EMAIL" "Email address for system notifications (unattended-upgrades):"
    prompt_env_value "GITHUB_USERS" "GitHub usernames for SSH key fetching (space-separated, ED25519-only):"
    GITHUB_DEPLOY_KEYS="${GITHUB_DEPLOY_KEYS:-statisticsnorway/statbus}"
    prompt_env_value "GITHUB_DEPLOY_KEYS" "GitHub repo deploy-key sources for CI access (space-separated <org>/<repo>; default: statisticsnorway/statbus):"
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
    echo "  - Ensure APT sources are HTTPS (the goal — no http:// URI left)"
    echo "  - Rewrite any http://.../ubuntu URI to mirrors.edge.kernel.org (reliable HTTPS mirror)"
    echo "  - Leave already-HTTPS sources untouched (e.g. the image's own shipped mirror)"
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

    # STATBUS-207: the goal is HTTPS apt sources, not the kernel.org mirror
    # specifically. Detect ANY remaining http:// URI on an ACTIVE source
    # line (not presence/absence of mirrors.edge.kernel.org, and NOT a bare
    # http:// substring anywhere — stock Ubuntu/cloud-init sources files
    # routinely carry comment lines with http:// links, e.g. "# See
    # http://help.ubuntu.com/..." or a commented-out deb entry; matching
    # those would ghost-red an already-fully-HTTPS image). uri_line_re
    # anchors to real URI-bearing lines only — DEB822's "URIs:" stanza key,
    # or legacy "deb"/"deb-src" entries — the exact same anchor the
    # diagnostics dump below already used, now shared by detection and
    # verify too so all three agree on what counts as an active URI line.
    # An image that already ships its own HTTPS mirror (e.g. current
    # Hetzner Ubuntu 24.04 images) has nothing to rewrite, and forcing
    # kernel.org over it would be churn, not hardening. When a rewrite IS
    # needed, only the http://.../ubuntu shape is targeted, exactly as
    # before (the sed itself doesn't need the same anchor — once detection
    # is line-anchored, a sed that also touches a matching comment is
    # cosmetic, not a false-fail: verify is anchored too).
    local uri_line_re='^[[:space:]]*(URIs:|deb(-src)?[[:space:]])'

    # Handle both old-style sources.list and new DEB822 format
    if [[ -f "$sources_file" ]]; then
        log "Detected DEB822 format (ubuntu.sources)"

        if grep -qE "${uri_line_re}.*http://" "$sources_file"; then
            log "Backing up original sources..."
            cp "$sources_file" "${sources_file}.bak"

            log "Switching http:// URIs to HTTPS mirror..."
            sed -i 's|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' "$sources_file"
        else
            log "HTTPS sources already configured — shipped mirror: $(grep -E "$uri_line_re" "$sources_file" | grep -oE 'https://[^[:space:]]+' | head -1)"
        fi
    elif [[ -f "$old_sources" ]]; then
        log "Detected legacy sources.list format"

        if grep -qE "${uri_line_re}.*http://" "$old_sources"; then
            log "Backing up original sources..."
            cp "$old_sources" "${old_sources}.bak"

            log "Switching http:// URIs to HTTPS mirror..."
            sed -i 's|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' "$old_sources"
        else
            log "HTTPS sources already configured — shipped mirror: $(grep -E "$uri_line_re" "$old_sources" | grep -oE 'https://[^[:space:]]+' | head -1)"
        fi
    else
        log_warn "No standard sources file found"
    fi

    log "Updating package lists..."
    apt-get update -qq

    # Verification. Goal-stated (STATBUS-207): no http:// URI remains on
    # any ACTIVE source line, replacing the old kernel-org-presence grep —
    # an already-HTTPS image (no rewrite performed above) must verify
    # green too, and a comment mentioning http:// must never trip it
    # (same uri_line_re as detection above, so the two can never disagree
    # about what counts). On failure, print the actual URIs found so the
    # next triage never needs a live VM (the VM is torn down after every
    # harness run — the log is the only oracle).
    echo ""
    log "Verifying Stage 0..."
    if ! verify "HTTPS sources configured (no http:// URI remains)" "! grep -rqE '${uri_line_re}.*http://' /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null"; then
        log_error "Actual apt source URIs on this image (diagnose without a live VM):"
        grep -rnE "$uri_line_re" /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null | sed 's/^/    /'
    fi
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
    echo "  - Install tools: neovim, htop, net-tools, jnettop, git, acl, ripgrep, aptitude, tmux"
    echo "  - Set neovim as default editor"
    echo "  - Configure memory/swap settings for server workloads"
    echo "  - Install Docker CE with compose plugin"
    echo ""
    
    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 5"
        return 0
    fi
    
    log "Installing core tools..."
    # tmux (STATBUS-227 follow-up): replaces zellij's session-survival role
    # now that the Homebrew comfort layer (Stage 6) is gone — apt-managed,
    # patched by unattended-upgrades, same principle as the rest of this
    # list. Plain install: no auto-attach profile.d hook. An operator opts
    # in with `tmux` / `tmux attach` like any other server; this is a
    # deliberate default, reversible later, not an oversight.
    apt-get install -y neovim htop net-tools jnettop git acl ripgrep aptitude tmux
    
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
    verify "tmux installed" "which tmux"
    verify "System tuning applied" "test -f /etc/sysctl.d/20-server-tuning.conf"
    verify "Docker installed" "which docker"
    verify "Docker running" "systemctl is-active docker"
    verify "Docker Compose installed" "docker compose version"
    
    pause
}

# =============================================================================
# Stage 6: User Setup (devops)
# =============================================================================

stage_user_setup() {
    log_header "Stage 6: User Setup (devops)"

    if stage_skipped 6; then
        log_warn "Stage 6 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Create 'devops' user with passwordless sudo"
    echo "  - Fetch SSH keys (ED25519-only) from GitHub:"
    echo "      Users:       ${GITHUB_USERS:-<not configured>}"
    echo "      Deploy keys: ${GITHUB_DEPLOY_KEYS:-<not configured>}"
    echo "  - Generate ed25519 SSH keypair for devops"
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
    populate_authorized_keys "devops" "$GITHUB_USERS" "$GITHUB_DEPLOY_KEYS"

    # Generate ed25519 SSH keypair for devops if not present, and ensure
    # mode/ownership on the resulting files.
    sudo -i -u devops bash <<'DEVOPS_KEYPAIR'
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "devops@$(hostname --fqdn)"
fi
chmod 600 ~/.ssh/id_ed25519 2>/dev/null || true
chmod 644 ~/.ssh/id_ed25519.pub 2>/dev/null || true
DEVOPS_KEYPAIR

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

    # STATBUS-227 / doc-032: the Homebrew comfort layer that used to live
    # here (Homebrew itself, build-essential, helix, bottom, zellij + its
    # auto-attach profile.d file) is DELETED, not slimmed for tests — this
    # is the real operator script, so there is no test-only profile to
    # diverge into. It contradicted the hardening this same script
    # performs (a brew-installed openssl gets no updates from the
    # unattended-upgrades this script just configured, and it left a full
    # compiler toolchain — build-essential — on a hardened host), it
    # duplicated apt (helix/bottom are a second editor and monitor on top
    # of the neovim/htop Stage 5 already installs), and it was killing
    # rented test machines during the heaviest part of setup (STATBUS-227:
    # two arc-suite VMs went unresponsive mid-Homebrew-pour at rc.03). The
    # apt toolkit (neovim, htop, ripgrep, git, net-tools, jnettop, acl,
    # aptitude — Stage 5) remains: an operator diagnosing a box needs an
    # editor, a monitor and a grep, and those are small, apt-managed, and
    # patched by the mechanism this script already installs. Full ruling:
    # .backlog/docs/doc-032. tmux joined that same apt toolkit in Stage 5
    # (King-directed follow-up) to replace zellij's session-survival role —
    # plain install, no auto-attach hook; an operator opts in manually.

    # Verification
    echo ""
    log "Verifying Stage 6..."
    verify "devops user exists" "id devops"
    verify "devops has passwordless sudo" "test -f /etc/sudoers.d/devops"
    verify "devops SSH directory exists" "test -d /home/devops/.ssh"
    if getent group docker >/dev/null; then
        verify "devops is in docker group" "id -nG devops | tr ' ' '\n' | grep -qx docker"
    fi

    if [[ -n "$GITHUB_USERS" || -n "$GITHUB_DEPLOY_KEYS" ]]; then
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
    echo "  - Populate ~$user/.ssh/authorized_keys (ED25519-only) from GitHub:"
    echo "      Users:       ${GITHUB_USERS:-<not configured>}"
    echo "      Deploy keys: ${GITHUB_DEPLOY_KEYS:-<not configured>}"
    echo "  - Enable systemd linger so user units survive logout"
    echo ""
    echo "  Operators (and CI deploy workflows) SSH as '$user' to install"
    echo "  and operate StatBus. The repo deploy key is required for the"
    echo "  GitHub Actions deploy-to-* workflows to land on this box."
    echo ""

    if [[ -z "$GITHUB_USERS" && -z "$GITHUB_DEPLOY_KEYS" ]]; then
        log_warn "No GitHub users OR deploy keys configured — SSH keys won't be fetched and"
        log_warn "nobody (operator or CI) will be able to SSH in as '$user' until you add keys manually."
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
    populate_authorized_keys "$user" "$GITHUB_USERS" "$GITHUB_DEPLOY_KEYS"

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
    if [[ -n "$GITHUB_USERS" || -n "$GITHUB_DEPLOY_KEYS" ]]; then
        verify "$user authorized_keys populated" "test -s /home/$user/.ssh/authorized_keys"
    fi
    verify "$user linger enabled" "loginctl show-user $user -p Linger 2>/dev/null | grep -q 'Linger=yes'"

    pause
}

# =============================================================================
# Stage 8: CI Command Allowlist (sshdo)
# =============================================================================

stage_ci_allowlist() {
    log_header "Stage 8: CI Command Allowlist (sshdo)"

    if stage_skipped 8; then
        log_warn "Stage 8 skipped via SKIP_STAGES"
        return 0
    fi

    # STATBUS-259. /etc/sshdoers is the byte-pinned allowlist every inbound CI
    # ssh command is checked against — the fleet's access policy. It was
    # established by hand in a root session and never joined the path built for
    # exactly this, so the live policy could drift from the reviewed copy
    # silently, in either direction. Its own header recorded the consequence:
    # "Managed by hand."
    #
    # The allowlist SHAPE was never the problem — least privilege on an inbound
    # credential door is the right shape. What violated doctrine is that every
    # other fix reaches a box through code, while the access policy alone
    # reached it through a person editing a root file over SSH.
    #
    # This stage does not invent a delivery mechanism. It makes the allowlist a
    # stage of the one that already exists, so an allowlist change becomes a
    # reviewed commit plus a stage re-run instead of a privileged session.
    #
    # RUN THIS STAGE ALONE with the existing skip mechanism — no new flag:
    #   sudo ./harden.sh --non-interactive --skip-stages "0 1 2 3 4 5 6 7"

    # STATBUS-280. Stage 8 is OPT-IN. rc.10's smoke legs failed the default
    # sequence deterministically: almost no installation has a CI door, so an
    # unset SSHDOERS_REF here means the stage was NEVER REQUESTED — the
    # majority and correct case — categorically different from a stage whose
    # absence is always a gap. Every acceptance before the smoke legs ran a
    # MODIFIED invocation (stage-8-only, or stage-3-only); none ran the
    # unmodified default every real external operator actually runs, and
    # that default hit a REQUIRED refusal demanding a fleet-only variable — a
    # product-must-not-know-doors violation reaching an external box through
    # ops/. Absence of the ref is silent success here, nothing more; once a
    # ref IS provided, every refusal below (bad ref, missing host directory,
    # sshdo absent) is unchanged — this only affects the never-requested case.
    #
    # COMMIT-ADDRESSED, NEVER master (architect ruling c3), when a door IS
    # requested. A security artifact installed from a moving ref cannot be
    # named afterwards: "what policy is live?" would have no answer, because
    # master moved.
    #
    # Rejected discriminator, recorded: keying opt-in on ops/<host>/ existing
    # instead of on SSHDOERS_REF — cannot check the repo for a host directory
    # without a ref to check it at.
    local ref="${SSHDOERS_REF:-}"
    if [[ -z "$ref" ]]; then
        log_warn "Stage 8 not run: no CI command door declared for this host. To install one, set SSHDOERS_REF."
        return 0
    fi

    local host="${SSHDOERS_HOST:-}"
    if [[ -z "$host" ]]; then
        # Default to the first label of the FQDN: niue.statbus.org -> niue,
        # which is already the repo's layout (ops/<host>/sshdoers).
        host="$(hostname --fqdn 2>/dev/null | cut -d. -f1)"
    fi
    local url="https://raw.githubusercontent.com/statisticsnorway/statbus/${ref}/ops/${host}/sshdoers"

    echo "This stage will:"
    echo "  - Fetch the reviewed allowlist for host '$host' at ref '$ref':"
    echo "      $url"
    echo "  - Install it BYTE FOR BYTE as /etc/sshdoers, PRESERVING the live"
    echo "    file's mode and ownership (sshdo reads it as the slot user —"
    echo "    tightening it would deny every CI command on the fleet)"
    echo "  - Publish /etc/sshdoers.sha256 world-readable beside it, so anyone —"
    echo "    including the release preflight over an unprivileged door — can"
    echo "    check that the live policy is the reviewed one"
    echo ""
    echo "  The allowlist is what every inbound CI ssh command is checked"
    echo "  against. Installing a copy that differs from the live file CHANGES"
    echo "  the fleet's access policy; an entry that disappears is a workflow"
    echo "  that stops working."
    echo ""

    if [[ -z "$host" ]]; then
        log_error "Cannot determine the host name for the allowlist (hostname --fqdn gave nothing)."
        log_error "Set SSHDOERS_HOST=<host> explicitly and re-run this stage."
        FAILED_VERIFICATIONS+=("Stage 8: host name for the allowlist could not be determined")
        return 0
    fi

    # STATBUS-269. A mistyped SSHDOERS_HOST, or a container whose short
    # hostname just doesn't match any reviewed directory, previously surfaced
    # three checks later as "sshdo enforcer absent" or "allowlist fetch
    # failed" — both name ops/${host}/... as though the canonical file were
    # simply missing, sending the operator chasing a file instead of the
    # typo. One check, up front, covers both causes: probe $url — the EXACT
    # file this stage is about to fetch, same host/ref/path — before $host is
    # used in any other message.
    #
    # Checks the FILE on raw.githubusercontent.com, not the directory via
    # api.github.com: identical failure modes to the real fetch this
    # precedes, no second network dependency (a separately rate-limited API),
    # and it verifies the thing that actually matters.
    #
    # STATUS IS BRANCHED, NOT JUST COMPARED TO 200 (architect amendment). A
    # 404 is a fact about ops/${host}/sshdoers at ref ${ref} — nothing lives
    # there — but that fact has TWO indistinguishable causes: SSHDOERS_HOST
    # names the wrong directory, or SSHDOERS_REF names a commit where that
    # directory doesn't exist (empirically confirmed: raw.githubusercontent
    # returns 404 for a bad path AND for a bad ref alike, with no way to
    # tell them apart from the response). The message below names both, not
    # just the host — an operator with a typo'd REF and a correct HOST must
    # not be sent checking the one variable that was already right. Any
    # OTHER non-200 — a 403 rate limit (hit in practice), a 5xx, a network
    # failure reported as "000" — is NOT a statement about the host or the
    # ref at all; it means the check itself could not look. Both branches
    # still refuse (fail closed) — only the stated reason changes.
    #
    # NO -f, NO "|| echo 000": curl's own -w already prints "000" when no
    # HTTP response was received at all (its documented behaviour for a
    # failed transfer), so both are redundant — and -f makes them actively
    # wrong. -f raises curl's exit status to nonzero on a 4xx/5xx response,
    # but -w had ALREADY written the real code to stdout before that exit;
    # the "||" then fires on that nonzero exit and appends "000" onto the
    # code curl already printed, so a 404 was captured as literal "404000"
    # (caught empirically: a real Docker run of the typo-host case reported
    # "HTTP 404000" instead of 404, silently routing a real 404 into the
    # could-not-verify branch instead of the host-is-wrong branch). Dropping
    # both leaves curl's own single, correctly-formed code as the only thing
    # ever written here, confirmed against all three real cases: 200, 404,
    # and 000 (network-unreachable, tested with an invalid host so no live
    # rate limit was needed).
    local host_dir_status
    host_dir_status="$(curl -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
    if [[ "$host_dir_status" == "404" ]]; then
        log_error "Nothing found at ops/${host}/sshdoers for ref ${ref} (HTTP 404)."
        log_error "Either SSHDOERS_HOST names the wrong directory, or SSHDOERS_REF names a commit"
        log_error "where that file does not exist — raw.githubusercontent returns 404 for both."
        log_error "Checked: $url"
        log_error "Set SSHDOERS_HOST=<the correct directory under ops/> and/or SSHDOERS_REF=<a commit"
        log_error "where it exists>, then re-run this stage."
        FAILED_VERIFICATIONS+=("Stage 8: nothing at ops/${host}/sshdoers for ref ${ref} (HTTP 404)")
        return 0
    elif [[ "$host_dir_status" != "200" ]]; then
        log_error "Could not verify whether ops/${host}/ exists (HTTP $host_dir_status) — this is not a statement about the host."
        log_error "Checked: $url"
        log_error "Retry, or check network connectivity / GitHub rate limits, then re-run this stage."
        FAILED_VERIFICATIONS+=("Stage 8: could not verify ops/${host}/ (HTTP ${host_dir_status})")
        return 0
    fi

    # THE ENFORCER MUST EXIST. An allowlist without sshdo in front of it looks
    # configured and enforces nothing — worse than an absent file, because the
    # file's presence reads as evidence the door is closed.
    if [[ ! -x /usr/local/bin/sshdo ]]; then
        log_error "/usr/local/bin/sshdo is missing or not executable — refusing to install an allowlist nothing enforces."
        log_error "An allowlist without its enforcer looks configured while permitting everything the forced command allows."
        log_error "Install sshdo first (ops/${host}/sshdo holds the canonical copy), then re-run this stage."
        FAILED_VERIFICATIONS+=("Stage 8: sshdo enforcer absent")
        return 0
    fi

    if ! ask_yes_no "Run this stage?"; then
        log "Skipping Stage 8"
        return 0
    fi

    local staged="/tmp/sshdoers.stage.$$"
    trap 'rm -f "/tmp/sshdoers.stage.$$"' RETURN

    log "Fetching the reviewed allowlist for '$host'..."
    if ! curl -fsSL "$url" -o "$staged"; then
        log_error "Could not fetch $url"
        log_error "Nothing was changed. Check the host name, the ref, and network reachability."
        FAILED_VERIFICATIONS+=("Stage 8: allowlist fetch failed for $host@$ref")
        return 0
    fi

    # VALIDATE BEFORE INSTALLING. A truncated fetch fails CLOSED (fewer
    # permitted commands), so it would not open the door — but it would break
    # every CI path on the box while looking like a successful run. Both grammar
    # lines are load-bearing: `match hexdigits` is what lets a 40-char SHA be
    # matched at all, and its absence would silently refuse the pg_regress
    # runner and any commit-addressed entry.
    if [[ ! -s "$staged" ]]; then
        log_error "The fetched allowlist is EMPTY — refusing to install it."
        FAILED_VERIFICATIONS+=("Stage 8: fetched allowlist was empty")
        return 0
    fi
    local missing=""
    grep -q '^match hexdigits' "$staged" || missing="match hexdigits"
    grep -q '^syslog ' "$staged" || missing="${missing:+$missing, }syslog"
    if [[ -n "$missing" ]]; then
        log_error "The fetched allowlist is missing required grammar: $missing"
        log_error "That is what a truncated or wrong-file fetch looks like. Refusing to install it."
        FAILED_VERIFICATIONS+=("Stage 8: fetched allowlist missing grammar ($missing)")
        return 0
    fi

    # ASK THE ENFORCER ITSELF whether the file is valid, before installing it.
    # `sshdo --check` runs the very parser that will read this file in anger, so
    # it catches what a grep cannot: invalid directives, clashing allow/disallow
    # rules, and entries naming users that do not exist on this host.
    #
    # The two checks are not redundant — they answer different questions. The
    # grep above asks "is this the file we think it is?" (a truncation can be
    # perfectly valid syntax); this asks "will sshdo accept it?".
    log "Validating the fetched allowlist with sshdo's own parser..."
    local check_out
    check_out="$(/usr/local/bin/sshdo --check "$staged" 2>&1 || true)"
    [[ -n "$check_out" ]] && printf '%s\n' "$check_out" | sed 's/^/    /'

    # THE EXIT CODE IS NOT THE VERDICT HERE, and that was worth testing rather
    # than assuming. `sshdo --check` counts "No such user" into its error total
    # and exits non-zero for it (verified: exit 9 against this repo's own
    # allowlist on a machine without the slot accounts). On a freshly-provisioned
    # host, where Stage 8 may run before every slot user exists, a perfectly
    # valid allowlist would then be REJECTED and provisioning would stop for a
    # condition of the HOST rather than a fault in the FILE.
    #
    # So the two classes are separated by what the parser calls them:
    #   error:   the config is invalid — sshdo would refuse to work. REFUSE.
    #   warning: something about this host (a user not created yet, a clash
    #            worth seeing). SURFACE IT, loudly, and continue.
    if printf '%s\n' "$check_out" | grep -q '^error:'; then
        log_error "sshdo --check found INVALID CONFIG in the fetched allowlist — refusing to install it."
        log_error "Installing a config sshdo cannot parse denies every CI command on this host, and"
        log_error "the refusal an operator sees blames a missing entry rather than the file."
        FAILED_VERIFICATIONS+=("Stage 8: sshdo --check reported invalid config")
        return 0
    fi
    if printf '%s\n' "$check_out" | grep -q '^warning: No such user'; then
        log_warn "The allowlist names users that do not exist on this host (listed above)."
        log_warn "Those entries are inert until the accounts are created — expected on a fresh"
        log_warn "host, but on a live one it means a CI path is silently dead."
    fi

    # SHOW THE CHANGE. The operator is about to alter the fleet's access policy;
    # they should see whether anything actually differs before it happens.
    if [[ -f /etc/sshdoers ]]; then
        if cmp -s "$staged" /etc/sshdoers; then
            log "Live /etc/sshdoers already matches the reviewed copy — this run is a no-op for the file itself."
        else
            log_warn "The live /etc/sshdoers DIFFERS from the reviewed copy. Lines that change:"
            diff -u /etc/sshdoers "$staged" | sed 's/^/    /' || true
            log_warn "A line that disappears is a CI path that stops working. Backup below."
            cp -a /etc/sshdoers "/root/sshdoers.pre-259.$(date -u +%Y%m%dT%H%M%SZ)"
            log "Backed up the previous allowlist under /root/sshdoers.pre-259.*"
        fi
    else
        log_warn "No /etc/sshdoers exists yet — this stage is establishing it for the first time."
    fi

    # INSTALL BYTE FOR BYTE. No envsubst, no comment stripping, no
    # normalisation: the release preflight hashes the REPO file and compares it
    # to the hash published here, so any transformation would make two identical
    # policies look like drift and fail every release.
    #
    # ⚠ THE MODE IS PRESERVED, NEVER CHOSEN (architect ruling c2 — a hazard, not
    # a preference). Read out of sshdo's source rather than inferred, because the
    # ruling required exactly that:
    #
    #   · sshdo is invoked through `command="/usr/local/bin/sshdo"` in the SLOT
    #     USER's authorized_keys, so it runs AS THAT USER, and load_config()
    #     plain-open()s /etc/sshdoers as that user (ops/niue/sshdo:299). There is
    #     no setuid anywhere in it.
    #
    #   · sshdo imposes NO mode requirement of its own — there is no stat, no
    #     permission check, no refusal on a group- or world-readable config
    #     anywhere in the file. The ONLY requirement is that the invoking user
    #     can read it.
    #
    #   · AND AN UNREADABLE CONFIG DOES NOT FAIL LOUDLY. On IOError, load_config
    #     logs `configerror` to syslog and RETURNS AN EMPTY CONFIG
    #     (ops/niue/sshdo:477-481). check_auth then finds nothing allowed, so
    #     every command is refused with the generic "command not in allowlist"
    #     message — which sends whoever is debugging it hunting for a missing
    #     ENTRY rather than an unreadable FILE.
    #
    # So tightening to 0600 root:root would deny every CI command on the fleet
    # AND disguise the cause, from a stage that printed success. On an existing
    # file the current mode and ownership are carried over untouched and
    # reported. A first-ever install picks 0644 — the least that guarantees the
    # readability sshdo actually needs, with no stricter requirement to satisfy.
    local mode owner
    if [[ -f /etc/sshdoers ]]; then
        mode="$(stat -c '%a' /etc/sshdoers)"
        owner="$(stat -c '%U:%G' /etc/sshdoers)"
        log "Preserving the live mode and ownership: $owner $mode"
    else
        mode="0644"
        owner="root:root"
        log_warn "No existing /etc/sshdoers — establishing it as $owner $mode."
        log_warn "It must stay readable by the slot users: sshdo reads it AS the invoking user."
    fi
    log "Installing /etc/sshdoers ($owner $mode)..."
    install -o "${owner%%:*}" -g "${owner##*:}" -m "$mode" "$staged" /etc/sshdoers

    # PUBLISH THE HASH, NOT THE FILE. Not because the policy is secret — the slot
    # users must be able to read it, as above — but because a hash is the right
    # shape for this job: it detects drift without anyone parsing the policy, and
    # it records exactly which bytes were installed.
    log "Publishing /etc/sshdoers.sha256 (world-readable)..."
    sha256sum /etc/sshdoers | awk '{print $1}' > /etc/sshdoers.sha256
    chown root:root /etc/sshdoers.sha256
    chmod 0644 /etc/sshdoers.sha256

    # Verification
    echo ""
    log "Verifying Stage 8..."
    verify "/etc/sshdoers exists" "test -s /etc/sshdoers"
    verify "/etc/sshdoers kept the mode this stage installed it with" \
        "test \"\$(stat -c '%a' /etc/sshdoers)\" = \"${mode#0}\" -o \"\$(stat -c '%a' /etc/sshdoers)\" = \"$mode\""
    # The one property that must hold whatever the mode is: sshdo runs as the
    # slot user, so the file it reads has to be readable by someone other than
    # root. A stage that left it root-only would have denied the whole fleet.
    verify "/etc/sshdoers is readable by non-root (sshdo runs as the slot user)" \
        "test \"\$(stat -c '%a' /etc/sshdoers | tail -c 3)\" != '00'"
    verify "/etc/sshdoers.sha256 exists and is world-readable" \
        "test -s /etc/sshdoers.sha256 && test \"\$(stat -c '%a' /etc/sshdoers.sha256)\" = '644'"
    # The published hash must describe the file that is actually installed —
    # a stale hash would let real drift pass the preflight unnoticed, which is
    # the one failure this whole mechanism exists to prevent.
    verify "published hash matches the installed file" \
        "test \"\$(sha256sum /etc/sshdoers | awk '{print \$1}')\" = \"\$(cat /etc/sshdoers.sha256)\""
    verify "installed allowlist matches the reviewed copy byte for byte" "cmp -s '$staged' /etc/sshdoers"
    verify "sshdo enforcer present" "test -x /usr/local/bin/sshdo"
    # Same distinction as above: assert the parser reports no `error:` line, not
    # that its exit code is zero — a "No such user" warning must not fail the run.
    verify "sshdo parses the installed allowlist without errors" \
        "! /usr/local/bin/sshdo --check /etc/sshdoers 2>&1 | grep -q '^error:'"

    echo ""
    log "Live allowlist hash: $(cat /etc/sshdoers.sha256)"
    echo ""
    echo "  PROVE THE GATE STILL ENFORCES from a machine holding the CI key —"
    echo "  not from this root session, since root does not pass through the door:"
    echo "      ssh <ci-user>@$(hostname --fqdn) \"<an allowlisted command>\"   # allowed"
    echo "      ssh <ci-user>@$(hostname --fqdn) \"ls /\"                        # must be REFUSED"
    echo ""

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
                echo "  6  User Setup (devops user, SSH keys)"
                echo "  7  StatBus Service Account (statbus user)"
                echo "  8  CI Command Allowlist (sshdo /etc/sshdoers + published hash)"
                echo ""
                echo "Stage 8 environment:"
                echo "  SSHDOERS_HOST=<host>  Which ops/<host>/sshdoers to install"
                echo "                        (default: first label of hostname --fqdn)"
                echo "  SSHDOERS_REF=<commit>  REQUIRED. The commit the reviewed allowlist"
                echo "                         lives at. Deliberately not defaulted: a policy"
                echo "                         installed from a moving ref cannot be named later."
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
    stage_ci_allowlist

    log_header "Setup Complete!"

    echo "Summary of configuration:"
    echo "  - SSH hardened (key-only authentication)"
    echo "  - Automatic security updates enabled"
    echo "  - CrowdSec intrusion detection active"
    echo "  - UFW firewall enabled"
    echo "  - Docker installed"
    echo "  - devops user created (ops/admin)"
    echo "  - ${SERVICE_USER:-statbus} service account created (for StatBus install)"
    echo "  - CI command allowlist installed from the repo, with a published hash"
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

    # STATBUS-207: the only point in main() that turns any verify()
    # failure, from any stage, into a non-zero process exit. Checked AFTER
    # every stage has run to completion (maximal diagnostics — the VM is
    # torn down right after this run, so fail-fast would hide whatever
    # came after the first ✗) so a real regression anywhere finally
    # reaches the caller's (harness's) exit code instead of vanishing into
    # stage output nobody's automation checks.
    if [[ ${#FAILED_VERIFICATIONS[@]} -gt 0 ]]; then
        echo ""
        log_error "${#FAILED_VERIFICATIONS[@]} verification(s) failed across the run:"
        for failed in "${FAILED_VERIFICATIONS[@]}"; do
            echo "  ✗ $failed"
        done
        exit 1
    fi
}

main "$@"
