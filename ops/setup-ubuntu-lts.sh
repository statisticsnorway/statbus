#!/bin/bash
#
# setup-ubuntu-lts.sh
# Ubuntu LTS Server Setup Script
#
# Usage:
#   sudo -i      # root login shell (HOME=/root); plain sudo is refused
#   # STATBUS-488 prepare fetch: use the setup script of the release you install.
#   # Set VERSION to the tag you will install (e.g. VERSION=v2026.03.0, then pass the
#   # same --version to install.sh); left unset it resolves the stable channel the
#   # same way install.sh does.
#   VERSION="${VERSION:-$(curl -sL https://api.github.com/repos/statisticsnorway/statbus/releases/latest | grep '"tag_name"' | cut -d'"' -f4)}"
#   curl -fsSL "https://raw.githubusercontent.com/statisticsnorway/statbus/${VERSION}/ops/setup-ubuntu-lts.sh" -o harden.sh
#   chmod +x harden.sh
#   ./harden.sh
#
# Non-interactive mode (uses .env values, runs all stages):
#   ./harden.sh --non-interactive
#
# Configuration is stored in ~/.setup-ubuntu.env
#

set -o pipefail

# =============================================================================
# Configuration
# =============================================================================

ENV_FILE="${HOME}/.setup-ubuntu.env"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
SUPPORTED_UBUNTU_VERSIONS=("24.04" "26.04")
# The StatBus release this copy belongs to. The release workflow stamps the tag
# here when it publishes the script (release.yaml, "Stage the install scripts");
# a copy taken straight from git keeps the placeholder and says so. One version:
# the release tag (STATBUS-537).
STATBUS_RELEASE="@STATBUS_RELEASE@"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
# Space-separated list of stage numbers to skip (e.g. "0 4"). Honored in both
# interactive and non-interactive mode. Also settable via --skip-stages.
SKIP_STAGES="${SKIP_STAGES:-}"
# STATBUS-491: cloud intent. Only a cloud installation is asked for CI
# deploy-key sources. Set by --cloud or CLOUD=true.
CLOUD="${CLOUD:-false}"
# Planned public name for this server, asked for when `hostname --fqdn` is a
# bare label. Persisted in the setup config so the installer can offer it.
SERVER_FQDN="${SERVER_FQDN:-}"
# Overridable host files: /etc/hosts is edited for the full name; the reboot
# flag is observed so the summary can say who caused the pending reboot.
HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
REBOOT_REQUIRED_FILE="${REBOOT_REQUIRED_FILE:-/var/run/reboot-required}"
REBOOT_REQUIRED_PKGS_FILE="${REBOOT_REQUIRED_PKGS_FILE:-/var/run/reboot-required.pkgs}"
REBOOT_REQUIRED_AT_START=false
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

# pkg_installed <name> — is this package installed, asked WITHOUT a pipe.
#
# STATBUS-227, root-caused at last. This script runs under `set -o pipefail`
# (see the top of the file), and `verify` evaluates its command in THIS shell,
# so a verify written as `dpkg -l | grep -q <pkg>` is subject to the canonical
# grep -q race: grep exits the instant it matches, closes the pipe, dpkg is
# killed by SIGPIPE with bytes still unwritten, and pipefail fails the pipeline
# DESPITE THE MATCH. The check reports ✗ for software that is installed.
#
# It is size-dependent, which is why it ROVED between scenarios and looked like
# VM flakiness for months: measured locally, a producer whose output is a few KB
# always succeeds, ~19KB fails 19 runs in 20, and ~39KB and up fails every time.
# The flip sits BELOW the 64KiB pipe buffer — this is a scheduling race about
# whether the producer has finished writing, not a buffer-capacity limit — so a
# longer package list simply widens the window.
#
# `${db:Status-Status}` is exactly the `^ii` the old crowdsec check spelled by
# hand, and it is STRICTER than the bare-name grep the unattended-upgrades check
# used: a purged-but-config-remaining package (`rc`) matched that grep and will
# now correctly read as not installed, which is what these verifies mean.
pkg_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

# STATBUS-494: every apt operation goes through these two helpers.
#
# WHY. On a lossy or intervening network apt fails transiently in two shapes
# that both look fatal and both clear on a retry with a fresh index: a
# connection closed mid-fetch ("Remote end closed connection"), and a
# complete-size file whose checksum does not match ("Hash Sum mismatch"). The
# second is what an intermediary rewriting the stream looks like — observed on
# a real installation in Uganda on 2026-10-13, where the operator's manual
# rerun of the same install then succeeded.
#
# Acquire::Retries makes apt itself re-fetch. Acquire::http::No-Cache tells an
# intermediary it must revalidate rather than serve its own copy.
# Acquire::http::Pipeline-Depth=0 avoids pipelining that older proxies mishandle.
# The retry is BOUNDED and then stops, with the cause named, instead of
# hammering a mirror that is genuinely serving something wrong.
APT_RETRY_ATTEMPTS="${APT_RETRY_ATTEMPTS:-3}"
APT_RETRY_DELAY_S="${APT_RETRY_DELAY_S:-5}"

apt_retry() {          # apt_retry <label> <apt-get args...>
    local label="$1" attempt rc=0
    shift
    for (( attempt=1; attempt<=APT_RETRY_ATTEMPTS; attempt++ )); do
        if apt-get -o Acquire::Retries=3 \
                   -o Acquire::http::No-Cache=true \
                   -o Acquire::http::Pipeline-Depth=0 "$@"; then
            [[ $attempt -gt 1 ]] && log_success "apt $label succeeded on attempt $attempt"
            return 0
        else
            rc=$?
        fi
        log_warn "apt $label failed (attempt $attempt/$APT_RETRY_ATTEMPTS, rc=$rc)"
        [[ $attempt -lt $APT_RETRY_ATTEMPTS ]] || break
        sleep $(( attempt * APT_RETRY_DELAY_S ))
        log "refreshing package lists before the next attempt"
        apt-get -qq -o Acquire::Retries=3 update >/dev/null 2>&1 || true
    done
    log_error "apt $label failed after $APT_RETRY_ATTEMPTS attempts (rc=$rc)."
    log_error "If the error above is a checksum mismatch, or a connection that closed mid-download, an intermediary is altering the download; the HTTPS sources stage (0) avoids it."
    return 1
}

# apt_install <label> <package...> — retried, and a failure is RECORDED like a
# verify() failure so main() exits non-zero, while the caller can stop before
# using a binary that was never installed.
apt_install() {
    local label="$1"
    shift
    apt_retry "$label" install -y "$@" || {
        verify "$label installed" "false"
        return 1
    }
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

# STATBUS-376 D7: the end-of-run summary is derived from what each stage
# actually did in THIS run. Stages record their outcome in one place as they
# run; the summary and next steps read that record instead of a static list.
#   ok       ran and every verification passed
#   skipped  skipped by the operator, SKIP_STAGES, or a measured condition
#   failed   ran but a verification or the stage itself failed
#   na       not part of this run at all (cloud-only work on a standalone box)
declare -A STAGE_OUTCOME=()

record_stage() {
    STAGE_OUTCOME[$1]="$2"
}

stage_outcome() {
    printf '%s' "${STAGE_OUTCOME[$1]:-not-run}"
}

stage_label() {
    case "$1" in
        0) echo "HTTPS APT sources" ;;
        1) echo "Base system" ;;
        2) echo "SSH hardening" ;;
        3) echo "Automatic security updates" ;;
        4) echo "Firewall and intrusion detection" ;;
        5) echo "Docker and core tools" ;;
        6) echo "devops user" ;;
        7) echo "StatBus service account" ;;
        8) echo "CI command allowlist" ;;
    esac
}

stage_configured_line() {
    case "$1" in
        0) echo "APT sources use HTTPS" ;;
        1) echo "Base system configured (etckeeper, bash history, locales)" ;;
        2) echo "SSH hardened (key-only authentication)" ;;
        3) echo "Automatic security updates enabled" ;;
        4) echo "CrowdSec intrusion detection and UFW firewall active" ;;
        5) echo "Docker and core tools installed" ;;
        6) echo "devops user created (ops/admin)" ;;
        7) echo "${SERVICE_USER:-statbus} service account created (for StatBus install)" ;;
        8) echo "CI command allowlist installed from the repo, with a published hash" ;;
    esac
}

# Run one stage and record whether it verified. A stage that already recorded
# skipped or na keeps that outcome; otherwise a failing return code or any
# verification failure during the stage marks it failed.
run_stage() {
    local n="$1" fn="$2" before after rc=0
    before="${#FAILED_VERIFICATIONS[@]}"
    "$fn" || rc=$?
    after="${#FAILED_VERIFICATIONS[@]}"
    if [[ -n "${STAGE_OUTCOME[$n]:-}" ]]; then
        return 0
    fi
    if [[ "$rc" -ne 0 || "$after" -gt "$before" ]]; then
        record_stage "$n" failed
    else
        record_stage "$n" ok
    fi
}

# Called once at the start of a run, before any stage can install updates, so
# the summary can tell Ubuntu's pre-existing pending reboot from one this run
# created. The flag's mere presence at the END says nothing about who caused it.
record_reboot_state() {
    if [[ -f "$REBOOT_REQUIRED_FILE" ]]; then
        REBOOT_REQUIRED_AT_START=true
    else
        REBOOT_REQUIRED_AT_START=false
    fi
}

print_run_summary() {
    local problems=${#FAILED_VERIFICATIONS[@]}
    local n outcome
    # STATBUS-502: never print a success headline over a failed run. The failure
    # list comes FIRST, and the headline follows from it.
    if [[ "$problems" -gt 0 ]]; then
        log_error "$problems verification(s) failed across the run:"
        for outcome in "${FAILED_VERIFICATIONS[@]}"; do
            echo "  ✗ $outcome"
        done
        echo ""
        log_header "Setup finished WITH PROBLEMS: $problems verification(s) failed"
    else
        log_header "Setup Complete!"
    fi

    echo "Summary of configuration:"
    for n in 0 1 2 3 4 5 6 7 8; do
        outcome="$(stage_outcome "$n")"
        case "$outcome" in
            na) continue ;;
            ok) echo "  - $(stage_configured_line "$n")" ;;
            skipped) echo "  - $(stage_label "$n") (Stage $n): skipped" ;;
            failed) echo "  - $(stage_label "$n") (Stage $n): failed" ;;
            *) echo "  - $(stage_label "$n") (Stage $n): not run" ;;
        esac
    done
    echo ""

    if [[ "$(stage_outcome 7)" == "ok" ]]; then
        echo "Next step: install StatBus as '${SERVICE_USER:-statbus}'."
        echo "  From this root shell:"
        echo "    sudo -iu ${SERVICE_USER:-statbus}"
        echo "    curl -fsSL https://statbus.org/install.sh | bash"
        echo "  Or sign in as '${SERVICE_USER:-statbus}' the way you normally reach this server, verify SSH key access, then run:"
        echo "    curl -fsSL https://statbus.org/install.sh | bash"
    else
        echo "  No follow-up from this run."
    fi
    echo ""

    # Reference only: these inspect controls the run installed, and are not a
    # to-do. They mean nothing when Stage 4 did not run.
    if [[ "$(stage_outcome 4)" == "ok" ]]; then
        echo "For later (optional):"
        echo "  See what the intrusion detection has blocked:  cscli metrics"
        echo "  Inspect the firewall rules:                    ufw status"
        echo ""
    fi

    if [[ -f "$REBOOT_REQUIRED_FILE" ]]; then
        if [[ "$REBOOT_REQUIRED_AT_START" == "true" ]]; then
            log_warn "Ubuntu reports a reboot is pending for updates installed before this run. Reboot at a convenient time."
            if [[ -s "$REBOOT_REQUIRED_PKGS_FILE" ]]; then
                log_warn "Packages waiting on that reboot: $(tr '\n' ' ' < "$REBOOT_REQUIRED_PKGS_FILE")"
            fi
        else
            log_warn "This run installed updates that need a reboot to take effect. Reboot at a convenient time."
        fi
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
#     CI automation gets ssh access without a personal key being in play.
#   * Idempotent: existing keys (added by hand, by a prior run, or by
#     another mechanism) are preserved. Re-runs converge — no duplicates.
#   * Each key is annotated with `# <source URL>` so an operator looking
#     at authorized_keys later can tell which line came from where.
#
# Usage (must be run as root; switches to target user via sudo internally):
#   populate_authorized_keys <target_user> "<users_list>" "<deploy_keys_list>"
#
# Both list args are whitespace-separated. Empty strings are valid.
# count_authorized_key_bodies — distinct key bodies (algorithm + base64) in a
# file, using the same token rules as the merge below. This is the before/after
# count that says how many keys were already there and how many the merge added.
count_authorized_key_bodies() {
    local file="$1"
    [[ -s "$file" ]] || { echo 0; return 0; }
    awk '
        {
            if ($0 ~ /^[[:space:]]*$/) next
            stripped = $0
            sub(/^[[:space:]]*/, "", stripped)
            if (substr(stripped, 1, 1) == "#") next
            n = split($0, t, /[[:space:]]+/)
            algo_idx = 0
            for (i = 1; i <= n; i++) {
                if (t[i] ~ /^(ssh-|ecdsa-|sk-)/) { algo_idx = i; break }
            }
            if (algo_idx == 0 || algo_idx + 1 > n) next
            keybody = t[algo_idx] " " t[algo_idx + 1]
            if (!seen[keybody]++) count++
        }
        END { print count + 0 }
    ' "$file"
}

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
    local before_count after_count added present_word

    before_count="$(count_authorized_key_bodies "$auth_keys")"

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

    after_count="$(count_authorized_key_bodies "$auth_keys")"
    added=$(( after_count - before_count ))
    [[ "$before_count" -eq 1 ]] && present_word="key" || present_word="keys"
    log_success "${target_user}: ${before_count} ${present_word} already present, ${added} added (${after_count} total in ${auth_keys})"
}

# STATBUS-501: the deploy keys to install for THIS run. Empty unless cloud
# intent is declared, so no call site can install our CI keys on a box that is
# not ours. One function, used by every call site.
deploy_keys_for_this_run() {
    [[ "${CLOUD:-false}" == "true" ]] && printf '%s' "${GITHUB_DEPLOY_KEYS:-}"
    return 0
}

# STATBUS-495: prove someone can still get in BEFORE password authentication is
# turned off. The owner's order, and the three cases it must tell apart:
#   1. the login account already has keys -> say so, install nothing;
#   2. no keys, but GITHUB_USERS names people -> install their keys and say what
#      was installed;
#   3. no keys and no GITHUB_USERS -> refuse, name the configuration entry, and
#      change nothing. A box with no keys must never be hardened into a lockout.
#
# Whatever happened above, the operator then has to confirm a real login from a
# second terminal. The default answer is NO, and NO means nothing is changed.
# The confirmation is a human step on purpose: only the person can prove it.
# In non-interactive runs ask_yes_no answers yes, so unattended preparations are
# unaffected.

# The login account's home directory, resolved in one place so the access gate
# can be exercised without touching a real home directory.
remote_access_home() { eval echo "~$1"; }

# The TCP port(s) sshd actually listens on, one per line, from the real
# listening sockets. Ubuntu 22.10+ socket-activates sshd: ssh.socket's
# ListenStream decides the port, while sshd_config's Port (what `sshd -T`
# reports) is ignored, so configuration is only a last-resort fallback. Empty
# output means the port could not be determined. Never assume 22: in Uganda
# the local operator had moved sshd to 713 on the server itself, and a
# firewall that opened only 22 locked the operator out.
ssh_listen_ports() {
    local ports
    # The real listeners, named by the process holding each socket. Under
    # socket activation sshd and systemd share the ssh.socket listener, so
    # sshd appears here on the port that actually accepts connections.
    ports="$(
        ss -H -ltnp 2>/dev/null | awk '
            index($0, "users:") && index($0, "(\"sshd\",") {
                n = split($4, parts, ":")
                if (parts[n] ~ /^[0-9]+$/) print parts[n]
            }'
    )"
    # Before the first connection the socket may be held by systemd alone and
    # sshd is absent from `ss`; ssh.socket's ListenStream is then the authority.
    if [[ -z "$ports" ]] && systemctl is-active --quiet ssh.socket 2>/dev/null; then
        ports="$(
            systemctl show ssh.socket -p Listen --value 2>/dev/null | awk '
                { for (i = 1; i <= NF; i++) {
                      n = split($i, parts, ":")
                      if (parts[n] ~ /^[0-9]+$/) print parts[n]
                  } }'
        )"
    fi
    # Last resort: sshd's effective configuration, for a classic sshd whose
    # socket process information `ss` does not show.
    if [[ -z "$ports" ]]; then
        ports="$(sshd -T 2>/dev/null | awk '$1 == "port" && $2 ~ /^[0-9]+$/ {print $2}')"
    fi
    if [[ -n "$ports" ]]; then
        printf '%s\n' "$ports" | sort -un
    fi
}

# Allow SSH through UFW: the Ubuntu OpenSSH app profile, always (it is the
# convention for this service, and with nothing listening on 22 nothing is
# exposed), plus every other port sshd really listens on as "Custom SSH". Rules
# this function created for a port sshd no longer listens on are removed, so a
# moved SSH port does not leave a stale opening; rules without that comment are
# never touched (owner ruling 2026-10-30). Refuse (return 1, no firewall change)
# when the ports cannot be determined: guessing is how an operator gets locked
# out of their own server, and OpenSSH alone may not be where sshd listens.
ufw_allow_ssh_ports() {
    local ports port stale stale_port
    ports="$(ssh_listen_ports)"
    if [[ -z "$ports" ]]; then
        log_error "Could not determine which port SSH listens on ('sshd -T' gave no port)."
        log_error "Refusing to enable the firewall, because it could close your SSH access."
        log_error "Check that sshd is installed and its configuration is valid (sudo sshd -t), then run this stage again."
        return 1
    fi
    # Only our own openings are candidates for removal: the "Custom SSH" comment
    # marks a rule this function added for a port sshd listened on.
    stale="$(
        ufw status 2>/dev/null | awk '
            /# Custom SSH[[:space:]]*$/ {
                n = split($1, parts, "/")
                if (n == 2 && parts[2] == "tcp" && parts[1] ~ /^[0-9]+$/) print parts[1]
            }' | sort -un
    )"
    for stale_port in $stale; do
        if ! printf '%s\n' $ports | grep -qx "$stale_port"; then
            log "Removing UFW rule for port $stale_port/tcp, which sshd no longer listens on."
            ufw delete allow "$stale_port/tcp"
        fi
    done
    log "Allowing SSH through UFW with the Ubuntu OpenSSH profile (port 22)."
    ufw allow OpenSSH
    for port in $ports; do
        # OpenSSH already covers 22; adding a port rule here would duplicate it.
        [[ "$port" = "22" ]] && continue
        log "Allowing SSH on port $port/tcp (the port sshd listens on)."
        ufw allow "$port/tcp" comment 'Custom SSH'
    done
}

ensure_remote_access() {
    local user="${1:-${SERVICE_USER:-statbus}}" home keys
    home="$(remote_access_home "$user")"
    keys="$home/.ssh/authorized_keys"

    if [[ -s "$keys" ]]; then
        log "I can see remote access is already set up for $user ($(grep -c '^ssh-' "$keys" 2>/dev/null || echo 0) key(s) in $keys)."
    elif [[ -n "${GITHUB_USERS:-}" ]]; then
        log "No keys are installed for $user yet; installing them from GITHUB_USERS (${GITHUB_USERS})..."
        if ! populate_authorized_keys "$user" "$GITHUB_USERS" "$(deploy_keys_for_this_run)"; then
            log_error "Could not install keys for $user. Nothing has been changed; fix the access, then run this script again."
            return 1
        fi
    else
        log_error "No keys are installed for $user and GITHUB_USERS is empty, so I cannot establish that anyone can log in."
        log_error "Set GITHUB_USERS in the setup configuration to the GitHub accounts whose keys may log in, then run this script again. Nothing has been changed."
        return 1
    fi

    echo ""
    log "Confirm you can still get in, before password authentication is disabled."
    local listen_ports
    listen_ports="$(ssh_listen_ports | paste -sd ' ' -)"
    if [[ -n "$listen_ports" ]]; then
        echo "  SSH is listening on port(s) $listen_ports on this server."
    else
        echo "  I could not determine which port SSH is listening on this server."
    fi
    echo "  In a second terminal, connect the way you normally reach this server"
    echo "  (your usual hostname and port; a router or NAT may map a different external port)."
    echo "  Answering no changes nothing: fix the access, then run this script again."
    if ! ask_yes_no "Did that connect?" n; then
        log_error "Remote access was not confirmed, so SSH has not been changed."
        return 1
    fi
    log_success "Remote access confirmed for $user"
    return 0
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
    [6]="GITHUB_USERS"                                   # User Setup (cloud-only stage)
    [7]="GITHUB_USERS SERVICE_USER"                       # StatBus Service Account
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
# setup-ubuntu-lts.sh configuration
# Generated: $(date -Iseconds)

# Email for unattended-upgrades notifications
ADMIN_EMAIL="${ADMIN_EMAIL:-}"

# Space-separated GitHub usernames for SSH key fetching
GITHUB_USERS="${GITHUB_USERS:-}"

# Space-separated GitHub repo deploy-key sources in <org>/<repo> form,
# fetched from https://github.com/<org>/<repo>.keys. Used to authorize
# CI deploy access (the GitHub Actions deploy workflows need the repository
# deploy key in the account's ~/.ssh/authorized_keys to ssh in).
# STATBUS-501: CLOUD-ONLY. That is our cloud and CI access model, so there is NO
# default here: a standalone installation must not carry a deploy-key source at
# all. Cloud runs get the SSB default in setup_env, behind the cloud-intent gate.
GITHUB_DEPLOY_KEYS="${GITHUB_DEPLOY_KEYS:-}"

# Space-separated extra locale codes without .UTF-8 suffix (e.g., "sq_AL nb_NO")
# The script adds .UTF-8 automatically. C.UTF-8 and en_US.UTF-8 are always included.
EXTRA_LOCALES="${EXTRA_LOCALES:-}"

# Username for the StatBus deployment service account created by Stage 7.
# This is the user operators will ssh as to run ./sb install and operate the
# deployment (distinct from devops, which is the ops/admin user from Stage 6).
SERVICE_USER="${SERVICE_USER:-statbus}"

# This server's full public name. Asked for when the host name is a bare
# label; the installer offers it as the default SITE_DOMAIN.
SERVER_FQDN="${SERVER_FQDN:-}"

EOF
    chmod 600 "$ENV_FILE"
}

# A plausible DNS name: at least two labels, each starting and ending with a
# letter or digit, hyphens only inside. The dot is what makes it a full name.
valid_dns_name() {
    local name="$1"
    [[ "$name" == *.* ]] || return 1
    [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

# Replace the single 127.0.1.1 line with "<fqdn> <short>", keeping every other
# line. Ubuntu's convention gives the host its own name on the loopback, which
# is what makes `hostname --fqdn` resolve without public DNS.
set_hosts_entry() {
    local fqdn="$1" short="$2" tmp
    if [[ ! -f "$HOSTS_FILE" ]]; then
        log_error "Cannot map the full name: $HOSTS_FILE does not exist."
        return 1
    fi
    tmp="$(mktemp "${HOSTS_FILE}.statbus.XXXXXX")" || return 1
    if ! awk -v entry="127.0.1.1 $fqdn $short" '
        $1 == "127.0.1.1" { if (!done++) print entry; next }
        { print }
        END { if (!done) print entry }
    ' "$HOSTS_FILE" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    cat "$tmp" > "$HOSTS_FILE"
    rm -f "$tmp"
}

# Resolve this server's full name before the StatBus stages need a site
# address. A dotted `hostname --fqdn` is already usable and is left alone.
# Otherwise the operator supplies the planned address (or SERVER_FQDN does in
# an unattended run), and the host is given that name the Ubuntu way: the same
# short name is kept when it already matches, and /etc/hosts gets one
# 127.0.1.1 line. Refusing before any mutation is deliberate: guessing a name
# would put a wrong address into certificates and the installer's default.
configure_server_fqdn() {
    local current fqdn short current_short
    current="$(hostname --fqdn 2>/dev/null || true)"
    if [[ "$current" == *.* ]]; then
        SERVER_FQDN="$current"
        log "This server's full name is $current; leaving the host name unchanged."
        return 0
    fi

    fqdn="${SERVER_FQDN:-}"
    if [[ -z "$fqdn" && "$NON_INTERACTIVE" == "true" ]]; then
        log_error "This server does not know its own full name ('hostname --fqdn' returned '${current:-<empty>}'), and SERVER_FQDN is not set in $ENV_FILE."
        log_error "Set SERVER_FQDN to the planned public address (for example statbus.example.org) and run this script again. Nothing has been changed."
        return 1
    fi

    while ! valid_dns_name "$fqdn"; do
        if [[ -n "$fqdn" ]]; then
            log_error "SERVER_FQDN='$fqdn' is not a plausible DNS name with a dot (for example statbus.example.org)."
        fi
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            return 1
        fi
        echo ""
        log "This server does not know its own full name ('hostname --fqdn' returned '${current:-<empty>}')."
        echo "  StatBus needs the public address people will use, with a dot, for example statbus.example.org."
        read -r -p "  Planned full address: " fqdn || return 1
    done

    short="${fqdn%%.*}"
    current_short="$(hostname 2>/dev/null || true)"
    if [[ -z "$current_short" ]]; then
        current_short="$(hostname -s 2>/dev/null || true)"
    fi
    if [[ "$current_short" != "$short" ]]; then
        log "Setting this server's short name to '$short'..."
        hostnamectl set-hostname "$short"
    else
        log "Keeping this server's short name '$short'."
    fi

    set_hosts_entry "$fqdn" "$short" || return 1
    verify "Full host name is $fqdn" "[[ \"\$(hostname --fqdn 2>/dev/null)\" == \"$fqdn\" ]]"
    SERVER_FQDN="$fqdn"
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        save_env
    fi
    return 0
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

    prompt_env_value "ADMIN_EMAIL" "Email address for system notifications (unattended-upgrades). Optional: leave blank for no unattended-upgrade notification emails:"
    prompt_env_value "GITHUB_USERS" "GitHub usernames for SSH key fetching (space-separated, ED25519-only). This is operator/DevOps SSH access to the box for hardening and administration, not anything to do with StatBus data:"
    # STATBUS-501: the deploy-key source is cloud-only, and it is gated HERE,
    # where both the default and the question live. A standalone run leaves it
    # empty and is never asked about it.
    if [[ "$CLOUD" == "true" ]]; then
        GITHUB_DEPLOY_KEYS="${GITHUB_DEPLOY_KEYS:-statisticsnorway/statbus}"
        prompt_env_value "GITHUB_DEPLOY_KEYS" "GitHub repo deploy-key sources for CI access (space-separated <org>/<repo>; default: statisticsnorway/statbus):"
    fi
    prompt_env_value "EXTRA_LOCALES" "Extra locales to enable without .UTF-8 suffix (e.g., 'sq_AL nb_NO'):"
    SERVICE_USER="${SERVICE_USER:-statbus}"
    prompt_env_value "SERVICE_USER" "Deployment service-account username for Stage 7 (default: statbus):"

    save_env
    log_success "Configuration saved to $ENV_FILE"
}

# =============================================================================
# Stage 0: HTTPS APT Sources
# =============================================================================

# Enable each EXTRA_LOCALES entry in locale.gen. Accepts "nb_NO" or
# "nb_NO.UTF-8"/"nb_NO.utf8" (STATBUS-489). macOS sends LC_ALL=no_NO.UTF-8 for
# Norwegian, which glibc does not ship, so when nb_NO is declared we alias
# no_NO.UTF-8 to it unless the operator already defined a no_NO.UTF-8 alias.
enable_extra_locales() {
    local locales="$1" gen="$2" alias_file="$3" locale base pattern
    for locale in $locales; do
        base="${locale%%.*}"
        pattern="${base}.UTF-8 UTF-8"
        if grep -q "^# *${pattern}\$" "$gen"; then
            sed -i -e "s/^# *${pattern}\$/${pattern}/" "$gen"
            log "Enabled locale: ${base}.UTF-8"
        elif grep -q "^${pattern}\$" "$gen"; then
            log "Locale already enabled: ${base}.UTF-8"
        else
            log_warn "Locale not found in locale.gen: ${base}.UTF-8"
            continue
        fi
        if [[ "$base" == "nb_NO" ]] && ! grep -q '^no_NO.UTF-8[[:space:]]' "$alias_file" 2>/dev/null; then
            echo "no_NO.UTF-8 nb_NO.UTF-8" >> "$alias_file"
            log "Aliased no_NO.UTF-8 (sent by macOS ssh) to nb_NO.UTF-8"
        fi
    done
}

apt_http_sources() {
    local sources_dir="${1:-/etc/apt/sources.list.d}"
    local legacy_sources="${2:-/etc/apt/sources.list}"
    local source
    local found=1
    # sources.list(5): apt reads only .list and .sources entries in this directory.
    for source in "$sources_dir"/*.list "$sources_dir"/*.sources "$legacy_sources"; do
        [[ -f "$source" ]] || continue
        grep -nHE '^[[:space:]]*(URIs:|deb(-src)?[[:space:]]).*http://' "$source" && found=0
    done
    return "$found"
}

stage_https_sources() {
    log_header "Stage 0: HTTPS APT Sources"

    if stage_skipped 0; then
        record_stage 0 skipped
        log_warn "Stage 0 skipped via SKIP_STAGES"
        return 0
    fi

    # STATBUS-493: measure the network instead of asking the operator to guess.
    # Bounded probe: at most 5s connect / 8s total per URL.
    local http_ok=false https_ok=false
    log "Probing outbound HTTP and HTTPS (8s max each)..."
    curl -sS -o /dev/null --connect-timeout 5 --max-time 8 http://archive.ubuntu.com/ubuntu/ 2>/dev/null && http_ok=true
    curl -sS -o /dev/null --connect-timeout 5 --max-time 8 https://mirrors.edge.kernel.org/ubuntu/ 2>/dev/null && https_ok=true
    log "Probe: HTTP $([[ $http_ok == true ]] && echo reachable || echo blocked), HTTPS $([[ $https_ok == true ]] && echo reachable || echo blocked)"

    if [[ "$http_ok" == "true" ]]; then
        record_stage 0 skipped
        log "HTTP egress is reachable, HTTPS sources are unnecessary. Skipping Stage 0"
        return 0
    fi

    echo "Outbound HTTP is blocked, so APT over http:// will fail. This stage will:"
    echo "  - Rewrite any http://.../ubuntu URI to mirrors.edge.kernel.org (reliable HTTPS mirror)"
    echo "  - Leave already-HTTPS sources untouched (e.g. the image's own shipped mirror)"
    echo ""

    if ! ask_yes_no "Switch APT sources to HTTPS?" y; then
        record_stage 0 skipped
        log "Skipping Stage 0"
        return 0
    fi

    local sources_file="/etc/apt/sources.list.d/ubuntu.sources"
    local old_sources="/etc/apt/sources.list"
    local backup_dir="/var/backups/statbus"

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
            mkdir -p "$backup_dir"
            cp "$sources_file" "$backup_dir/ubuntu.sources.$(date +%Y%m%d%H%M%S).bak"

            log "Switching http:// URIs to HTTPS mirror..."
            sed -i 's|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' "$sources_file"
        else
            log "HTTPS sources already configured — shipped mirror: $(grep -E "$uri_line_re" "$sources_file" | grep -oE 'https://[^[:space:]]+' | awk 'NR==1')"
        fi
    elif [[ -f "$old_sources" ]]; then
        log "Detected legacy sources.list format"

        if grep -qE "${uri_line_re}.*http://" "$old_sources"; then
            log "Backing up original sources..."
            mkdir -p "$backup_dir"
            cp "$old_sources" "$backup_dir/sources.list.$(date +%Y%m%d%H%M%S).bak"

            log "Switching http:// URIs to HTTPS mirror..."
            sed -i 's|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g' "$old_sources"
        else
            log "HTTPS sources already configured — shipped mirror: $(grep -E "$uri_line_re" "$old_sources" | grep -oE 'https://[^[:space:]]+' | awk 'NR==1')"
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
    if ! verify "HTTPS sources configured (no http:// URI remains)" "! apt_http_sources"; then
        log_error "Actual apt source URIs on this image (diagnose without a live VM):"
        apt_http_sources | sed 's/^/    /'
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
        record_stage 1 skipped
        log_warn "Stage 1 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install etckeeper for /etc version control"
    echo "  - Configure eternal bash history"
    echo "  - Configure system locales"
    echo ""
    
    if ! ask_yes_no "Run this stage?" y; then
        record_stage 1 skipped
        log "Skipping Stage 1"
        return 0
    fi
    
    log "Installing etckeeper..."
    apt_retry "update" update -qq || true
    if apt_install "etckeeper" etckeeper; then
        if [[ -d /etc/.git ]]; then
            log "etckeeper already initialized"
        else
            pushd /etc > /dev/null
            etckeeper init
            etckeeper commit "Initial commit before hardening"
            popd > /dev/null
        fi
    else
        log_error "etckeeper is not installed; skipping its initialization (the stage continues so its later checks still run)"
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
    enable_extra_locales "$EXTRA_LOCALES" /etc/locale.gen /etc/locale.alias
    
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
    verify "C.UTF-8 locale available" "LC_ALL=C.UTF-8 locale 2>&1 | grep -v 'Cannot set'"
    verify "en_US.UTF-8 locale available" "locale -a | grep 'en_US.utf8'"
    
    pause
}

# =============================================================================
# Stage 2: SSH Hardening
# =============================================================================

stage_ssh_hardening() {
    log_header "Stage 2: SSH Hardening"

    if stage_skipped 2; then
        record_stage 2 skipped
        log_warn "Stage 2 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Disable root password login (key-only)"
    echo "  - Disable password authentication"
    echo "  - Disable empty passwords"
    echo "  - Disable keyboard-interactive authentication"
    echo ""
    echo "Before it changes anything, this stage makes sure someone can still log in,"
    echo "and asks you to prove it from a second terminal. Answering no changes nothing."
    echo ""

    if ! ask_yes_no "Run this stage?" y; then
        record_stage 2 skipped
        log "Skipping Stage 2"
        return 0
    fi

    if ! ensure_remote_access "${SERVICE_USER:-statbus}"; then
        verify "Remote access confirmed before hardening" "false"
        pause
        return 0
    fi

    log "Configuring SSH..."
    cat > /etc/ssh/sshd_config.d/hardening.conf <<'EOF'
# SSH Hardening Configuration
# Generated by setup-ubuntu-lts.sh

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
        # The drop-in is a unit input change, so reload units before restarting;
        # without this systemd warns "unit file ... changed on disk" here.
        systemctl daemon-reload
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
    local login_home
    login_home="$(eval echo "~${SERVICE_USER:-statbus}")"
    verify "At least one authorized key exists for ${SERVICE_USER:-statbus}" "test -s '$login_home/.ssh/authorized_keys'"
    
    pause
}

# =============================================================================
# Stage 3: Automatic Updates
# =============================================================================

stage_auto_updates() {
    log_header "Stage 3: Automatic Updates"

    if stage_skipped 3; then
        record_stage 3 skipped
        log_warn "Stage 3 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install unattended-upgrades"
    echo "  - Configure automatic security updates"
    echo "  - Set up nightly update schedule (01:00 + random delay)"
    echo "  - Reboot at 03:15 when an update requires it (automatic reboots enabled)"
    echo "  - Set notification email: ${ADMIN_EMAIL:-<not configured>}"
    echo ""
    
    if ! ask_yes_no "Run this stage?" y; then
        record_stage 3 skipped
        log "Skipping Stage 3"
        return 0
    fi
    
    log "Installing unattended-upgrades..."
    apt_install "unattended-upgrades" unattended-upgrades
    
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
// Generated by setup-ubuntu-lts.sh

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

# STATBUS-496: reboot when an update requires it, at a fixed hour. The TIME alone
# does nothing without this switch -- unattended-upgrades defaults Automatic-Reboot
# to false -- so the stage used to advertise a reboot window that never happened.
# Owner decision 2026-10-13: enable it deliberately. With this on, the box reboots
# at the time below when /var/run/reboot-required is present after an upgrade run.
Unattended-Upgrade::Automatic-Reboot "true";
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
    verify "unattended-upgrades installed" "pkg_installed unattended-upgrades"
    verify "Auto-upgrades config exists" "test -f /etc/apt/apt.conf.d/20auto-upgrades"
    verify "Unattended-upgrades config exists" "test -f /etc/apt/apt.conf.d/50unattended-upgrades"
    verify "apt-daily timer override exists" "test -f /etc/systemd/system/apt-daily.timer.d/override.conf"
    verify "apt-daily-upgrade timer override exists" "test -f /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf"
    
    pause
}

# =============================================================================
# Stage 4: Security Tools (CrowdSec + UFW)
# =============================================================================

# Prove the firewall bouncer's key is one the local API actually accepts, and
# repair it when it is not. The key's presence in the bouncer configuration is
# not proof: a key kept from an earlier install passes that check while CrowdSec
# no longer knows it, so the bouncer runs inert and is refused with "access
# forbidden" (Uganda, statbus.ubos.org, 2026-10-30). Registration is the proof;
# when the bouncer is absent from the list, any stale entry by that name is
# deleted, a fresh key is created, written to $config, and never printed, and
# the bouncer is restarted so it reads the key.
ensure_bouncer_registered() {
    local config="${1:-${BOUNCER_CONFIG:-/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml}}"
    local name="${BOUNCER_NAME:-statbus-firewall-bouncer}"
    local bouncers key
    if [[ ! -f "$config" ]]; then
        log_error "Bouncer configuration $config is missing, so no API key can be stored."
        return 1
    fi
    bouncers="$(cscli bouncers list -o raw 2>/dev/null)" || bouncers=""
    if [[ -z "$bouncers" ]]; then
        # Older cscli builds may not know `-o raw`; the table form still names
        # every registered bouncer.
        bouncers="$(cscli bouncers list 2>/dev/null)" || bouncers=""
    fi
    if grep -qw "$name" <<<"$bouncers"; then
        log "Bouncer $name is registered with the local API."
        return 0
    fi
    log "Bouncer $name is not registered with the local API; creating a new API key..."
    cscli bouncers delete "$name" >/dev/null 2>&1 || true
    key="$(cscli bouncers add "$name" -o raw 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)"
    if [[ -z "$key" ]]; then
        log_error "Could not create a bouncer API key; the bouncer would be inert."
        return 1
    fi
    if grep -Eq '^api_key:' "$config"; then
        sed -i "s|^api_key:.*|api_key: ${key}|" "$config"
    else
        printf 'api_key: %s\n' "$key" >> "$config"
    fi
    log_success "Bouncer API key written to $config"
    systemctl restart crowdsec-firewall-bouncer 2>/dev/null || true
}

stage_security_tools() {
    log_header "Stage 4: Security Tools (CrowdSec + UFW)"

    if stage_skipped 4; then
        record_stage 4 skipped
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
        record_stage 4 skipped
        log "Skipping Stage 4"
        return 0
    fi
    
    log "Adding CrowdSec repository..."
    # STATBUS-499 owner decision, 2026-10-13: keep the vendor installer pipe. The
    # trust in the security vendor is unavoidable either way, so downloading the
    # script first would buy nothing but a round trip. No sudo here: this script
    # refuses a plain sudo from an operator home and requires a root login shell
    # (STATBUS-492), so by now we ARE root and HOME is root's -- the vendor script
    # cannot inherit an operator home.
    curl -s https://install.crowdsec.net | bash
    
    # STATBUS-498: CrowdSec FIRST, wait for its configuration, and only then the
    # firewall bouncer. Installing both in one transaction (what this stage did)
    # makes the bouncer postinst run before /etc/crowdsec/config.yaml exists: it
    # then reports "Error: while reading yaml file ... no such file or directory"
    # and "failed to create API key", so the bouncer runs with no credentials,
    # bans nothing, and still ticked green in this stage verification.
    log "Installing CrowdSec..."
    apt_install "crowdsec" crowdsec

    log "Waiting for the CrowdSec configuration..."
    for i in $(seq 1 30); do
        [ -f /etc/crowdsec/config.yaml ] && break
        sleep 1
    done
    if [[ ! -f /etc/crowdsec/config.yaml ]]; then
        log_error "CrowdSec did not write /etc/crowdsec/config.yaml; a bouncer installed without it would be inert."
        verify "CrowdSec wrote its configuration" "false"
        pause
        return 1
    fi

    log "Installing the CrowdSec firewall bouncer..."
    apt_install "crowdsec firewall bouncer" crowdsec-firewall-bouncer-nftables

    # The bouncer needs an API key to talk to the local API, and its package only
    # creates one when the configuration already exists. Prove the key is one the
    # local API accepts, and replace a stale one, so that "installed" can never
    # quietly mean "inert".
    BOUNCER_NAME="statbus-firewall-bouncer"
    BOUNCER_CONFIG="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
    ensure_bouncer_registered "$BOUNCER_CONFIG"

    log "Installing CrowdSec collections..."
    cscli collections install crowdsecurity/sshd

    log "Reloading CrowdSec..."
    systemctl reload crowdsec
    for i in $(seq 1 10); do
        cscli bouncers list 2>/dev/null | grep "$BOUNCER_NAME" >/dev/null && break
        sleep 1
    done
    systemctl restart crowdsec-firewall-bouncer 2>/dev/null || true
    
    log "Configuring UFW..."
    apt_install "ufw" ufw
    # Open the port(s) SSH really listens on, never an assumed 22. Refuse before
    # the firewall is enabled if they cannot be determined: enabling a
    # default-deny firewall that closes SSH locks the operator out (Uganda field
    # report, sshd on 713).
    if ! ufw_allow_ssh_ports; then
        log_error "The firewall was NOT enabled, so remote access is unchanged."
        return 1
    fi
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
    verify "Firewall bouncer installed" "pkg_installed crowdsec-firewall-bouncer || pkg_installed crowdsec-firewall-bouncer-nftables"
    # Installed is not the same as able to ban anything: without a key the bouncer
    # runs but is refused by the local API. These two fail the run rather than
    # ticking a box for a control that cannot work (STATBUS-498).
    verify "Firewall bouncer has an API key" "grep -Eq '^api_key:[[:space:]]*[^[:space:]]' /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
    verify "Firewall bouncer registered with the local API" "cscli bouncers list 2>/dev/null | grep -q statbus-firewall-bouncer"
    # Registered is not the same as running: a bouncer that keeps restarting
    # bans nothing, which is how the stale key showed up in Uganda.
    verify "Firewall bouncer running" "systemctl is-active crowdsec-firewall-bouncer"
    verify "SSHD collection installed" "cscli collections list | grep sshd"
    verify "UFW active" "ufw status | grep 'Status: active'"
    local ssh_port
    verify "OpenSSH allowed in UFW" "ufw status | grep -E '^OpenSSH[[:space:]]+ALLOW'"
    for ssh_port in $(ssh_listen_ports); do
        [[ "$ssh_port" = "22" ]] && continue
        verify "SSH port $ssh_port allowed in UFW" "ufw status | grep -E '^$ssh_port/tcp[[:space:]]+ALLOW'"
    done
    verify "HTTP allowed in UFW" "ufw status | grep '80/tcp'"
    verify "HTTPS allowed in UFW" "ufw status | grep '443/tcp'"
    verify "PostgreSQL allowed in UFW" "ufw status | grep '5432/tcp'"
    
    pause
}

# =============================================================================
# Stage 5: Core Tools & System Tuning
# =============================================================================

stage_core_tools() {
    log_header "Stage 5: Core Tools & System Tuning"

    if stage_skipped 5; then
        record_stage 5 skipped
        log_warn "Stage 5 skipped via SKIP_STAGES"
        return 0
    fi

    echo "This stage will:"
    echo "  - Install tools: neovim, htop, net-tools, jnettop, git, acl, ripgrep, aptitude, tmux"
    echo "  - Set neovim as default editor"
    echo "  - Configure memory/swap settings for server workloads"
    echo "  - Install Docker CE with compose plugin"
    echo ""
    
    if ! ask_yes_no "Run this stage?" y; then
        record_stage 5 skipped
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
    apt_install "core tools" neovim htop net-tools jnettop git acl ripgrep aptitude tmux
    
    log "Configuring neovim..."
    if [[ -f /etc/vim/vimrc ]] && ! grep -q "colorscheme elflord" /etc/vim/vimrc; then
        echo "colorscheme elflord" >> /etc/vim/vimrc
    fi
    update-alternatives --set editor /usr/bin/nvim 2>/dev/null || true
    
    log "Configuring system memory settings..."
    cat > /etc/sysctl.d/20-server-tuning.conf <<'EOF'
# Server Memory Tuning
# Generated by setup-ubuntu-lts.sh

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
    apt_install "docker prerequisites" ca-certificates curl gnupg
    
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list
    fi
    
    apt_retry "update" update -qq
    apt_install "docker" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # STATBUS-500: the account that will RUN StatBus needs the socket NOW, not two
    # stages later, and this stage's checks cannot see the difference: which docker,
    # systemctl is-active docker and docker compose version are all true for root
    # while an ordinary user is refused. That gap blocked a real installation in
    # Uganda: Docker installed, daemon running, socket permission denied.
    docker_user="${SERVICE_USER:-statbus}"
    if id "$docker_user" >/dev/null 2>&1; then
        # A case match, not a grep in a pipeline: this file runs under pipefail and
        # a grep exiting early can fail the pipeline it matched (STATBUS-227).
        case " $(id -nG "$docker_user") " in
            *" docker "*) log "$docker_user already has docker access" ;;
            *)
                log "Adding $docker_user to the docker group"
                usermod -aG docker "$docker_user"
                log_warn "$docker_user needs a NEW login session before it can use Docker; a fresh process (and runuser below) sees the group immediately"
                ;;
        esac
    else
        log_warn "$docker_user does not exist yet (it is created in a later stage); docker access is granted there"
    fi
    
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
    # Checked AS the account that will use it, not as root. A just-added group
    # member sees the group in a fresh process, which is what runuser gives us, so
    # this is a real check rather than a restatement of the daemon being up.
    verify "Docker usable by ${SERVICE_USER:-statbus}" "runuser -u ${SERVICE_USER:-statbus} -- docker info"
    
    pause
}

# =============================================================================
# Stage 6: User Setup (devops)
# =============================================================================

stage_user_setup() {
    # STATBUS-501: this stage is for OUR boxes only - the devops account with
    # passwordless sudo, and keys derived from our GitHub accounts. Without cloud
    # intent it is not part of the run AT ALL: no header, no prompt, no
    # explanation, because a customer's installation must never be told about our
    # support access model. Cloud intent lives in --help and doc/CLOUD.md.
    if [[ "${CLOUD:-false}" != "true" ]]; then
        record_stage 6 na
        return 0
    fi

    log_header "Stage 6: User Setup (devops)"

    if stage_skipped 6; then
        record_stage 6 skipped
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
        record_stage 6 skipped
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
    populate_authorized_keys "devops" "$GITHUB_USERS" "$(deploy_keys_for_this_run)"

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
        verify "devops is in docker group" "id -nG devops | tr ' ' '\n' | grep -x docker"
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
        record_stage 7 skipped
        log_warn "Stage 7 skipped via SKIP_STAGES"
        return 0
    fi

    local user="${SERVICE_USER:-statbus}" deploy_keys
    deploy_keys="$(deploy_keys_for_this_run)"

    echo "This stage will:"
    echo "  - Create Linux user '$user' with /home/$user as home"
    echo "  - Add '$user' to the docker group"
    echo "  - Populate ~$user/.ssh/authorized_keys (ED25519-only) from GitHub:"
    echo "      Users:       ${GITHUB_USERS:-<not configured>}"
    if [[ "${CLOUD:-false}" == "true" ]]; then
        echo "      Deploy keys: ${GITHUB_DEPLOY_KEYS:-<not configured>}"
    fi
    echo "  - Enable systemd linger so user units survive logout"
    echo ""
    if [[ "${CLOUD:-false}" == "true" ]]; then
        echo "  Operators (and CI deploy workflows) SSH as '$user' to install"
        echo "  and operate StatBus. The repo deploy key is required for the"
        echo "  approved GitHub Actions automation to land on this box."
    else
        echo "  Operators SSH as '$user' to install and operate StatBus."
    fi
    echo ""

    if [[ -z "$GITHUB_USERS" && -z "$deploy_keys" ]]; then
        log_warn "No GitHub users OR deploy keys configured — SSH keys won't be fetched and"
        log_warn "nobody (operator or CI) will be able to SSH in as '$user' until you add keys manually."
    fi

    if ! ask_yes_no "Run this stage?" y; then
        record_stage 7 skipped
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
    populate_authorized_keys "$user" "$GITHUB_USERS" "$(deploy_keys_for_this_run)"

    log "Enabling systemd --user linger for '$user' (so systemctl --user services persist)..."
    loginctl enable-linger "$user"

    # Verification
    echo ""
    log "Verifying Stage 7..."
    verify "$user user exists" "id $user"
    if getent group docker >/dev/null; then
        verify "$user is in docker group" "id -nG $user | tr ' ' '\n' | grep -x docker"
    fi
    verify "$user .ssh dir exists with correct mode" "test -d /home/$user/.ssh"
    if [[ -n "$GITHUB_USERS" || -n "$GITHUB_DEPLOY_KEYS" ]]; then
        verify "$user authorized_keys populated" "test -s /home/$user/.ssh/authorized_keys"
    fi
    verify "$user linger enabled" "loginctl show-user $user -p Linger 2>/dev/null | grep 'Linger=yes'"

    pause
}

# =============================================================================
# Stage 8: CI Command Allowlist (sshdo)
# =============================================================================

stage_ci_allowlist() {
    # STATBUS-501: /etc/sshdoers is OUR inbound CI access policy, so this stage
    # belongs to cloud runs only. Without cloud intent it is not part of the run
    # and says nothing - same rule as stage_user_setup above.
    if [[ "${CLOUD:-false}" != "true" ]]; then
        record_stage 8 na
        return 0
    fi

    log_header "Stage 8: CI Command Allowlist (sshdo)"

    if stage_skipped 8; then
        record_stage 8 skipped
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
        record_stage 8 skipped
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
    # matched at all, and its absence would silently refuse any
    # commit-addressed entry.
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
    if printf '%s\n' "$check_out" | grep '^error:' >/dev/null; then
        log_error "sshdo --check found INVALID CONFIG in the fetched allowlist — refusing to install it."
        log_error "Installing a config sshdo cannot parse denies every CI command on this host, and"
        log_error "the refusal an operator sees blames a missing entry rather than the file."
        FAILED_VERIFICATIONS+=("Stage 8: sshdo --check reported invalid config")
        return 0
    fi
    if printf '%s\n' "$check_out" | grep '^warning: No such user' >/dev/null; then
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
        "! /usr/local/bin/sshdo --check /etc/sshdoers 2>&1 | grep '^error:'"

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
                                    
  Ubuntu 24.04 / 26.04 LTS Server Setup Script
EOF
    echo -e "${NC}"
    if [[ "$STATBUS_RELEASE" == "@STATBUS_RELEASE@" ]]; then
        echo "  StatBus: development copy (not a release)"
    else
        echo "  StatBus: $STATBUS_RELEASE"
    fi
    echo "  Config:  $ENV_FILE"
    echo ""
}

check_prerequisites() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    check_supported_os
}

check_supported_os() {
    local ID="" VERSION_ID="" VERSION_CODENAME=""
    local supported

    if [[ ! -r "$OS_RELEASE_FILE" ]]; then
        log_error "Cannot read operating-system release information from $OS_RELEASE_FILE"
        return 1
    fi

    # Tests intentionally supply an os-release fixture.
    # shellcheck disable=SC1090
    . "$OS_RELEASE_FILE"

    if [[ "$ID" != "ubuntu" ]]; then
        log_error "Unsupported operating system: detected ${ID:-unknown} ${VERSION_ID:-unknown}; supported Ubuntu versions: ${SUPPORTED_UBUNTU_VERSIONS[*]}"
        return 1
    fi

    for supported in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
        if [[ "$VERSION_ID" == "$supported" ]]; then
            return 0
        fi
    done

    log_error "Unsupported Ubuntu version: detected ${VERSION_ID:-unknown}; supported versions: ${SUPPORTED_UBUNTU_VERSIONS[*]}"
    return 1
}

main() {
    # STATBUS-492: plain `sudo ./setup.sh` keeps HOME at the invoking user's
    # home, so root would write root-owned files there. Require a login shell.
    if [[ -n "${SUDO_USER:-}" && "$HOME" == "$(eval echo "~${SUDO_USER}")" ]]; then
        echo "Refusing to run with HOME=$HOME (the home of $SUDO_USER): open a root login shell with 'sudo -i' and run the script from there." >&2
        exit 1
    fi
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
            --cloud)
                CLOUD=true
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
                echo "  --cloud                    Cloud installation: also ask for CI deploy-key"
                echo "                              sources (GITHUB_DEPLOY_KEYS). Also CLOUD=true."
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
    record_reboot_state
    setup_env

    # The full host name is the site address StatBus will use. Resolve it before
    # any stage runs, but not for a run that will not install StatBus (for
    # example the firewall-only repair that skips Stages 5 and 7).
    if ! stage_skipped 5 || ! stage_skipped 7; then
        configure_server_fqdn || exit 1
    fi

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

    # Run stages, recording each outcome as it happens.
    run_stage 0 stage_https_sources
    run_stage 1 stage_base_system
    run_stage 2 stage_ssh_hardening
    run_stage 3 stage_auto_updates
    run_stage 4 stage_security_tools
    run_stage 5 stage_core_tools
    run_stage 6 stage_user_setup
    run_stage 7 stage_service_account
    run_stage 8 stage_ci_allowlist

    # STATBUS-376 D7/STATBUS-502: the summary and next steps are derived from
    # the outcomes recorded above, never from a static list of what a full run
    # would have done.
    print_run_summary

    # STATBUS-207: the only point in main() that turns any verify()
    # failure, from any stage, into a non-zero process exit. Checked AFTER
    # every stage has run to completion (maximal diagnostics — the VM is
    # torn down right after this run, so fail-fast would hide whatever
    # came after the first ✗) so a real regression anywhere finally
    # reaches the caller's (harness's) exit code instead of vanishing into
    # stage output nobody's automation checks. The failure LIST is printed
    # above, before the summary headline (STATBUS-502).
    if [[ "${#FAILED_VERIFICATIONS[@]}" -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
