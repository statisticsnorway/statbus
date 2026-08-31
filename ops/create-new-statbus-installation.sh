#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e
# Print all commands if VERBOSE is defined
if [ -n "${VERBOSE}" ]; then
    set -x
fi

# This script creates a new StatBus installation on niue.statbus.org
# Usage: ./create-new-statbus-installation.sh <deployment_code> <deployment_name> <version>
# Example: ./create-new-statbus-installation.sh ua "Ukraine StatBus" v2026.08.0-rc.10

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <deployment_code> <deployment_name> <version>"
    echo "Example: $0 ua \"Ukraine StatBus\" v2026.08.0-rc.10"
    exit 1
fi

DEPLOYMENT_SLOT_CODE="$1"
DEPLOYMENT_SLOT_NAME="$2"
VERSION="$3"
DOMAIN="${DEPLOYMENT_SLOT_CODE}.statbus.org"
DEPLOYMENT_USER="statbus_${DEPLOYMENT_SLOT_CODE}"
HOST="niue.statbus.org"

# VERSION (STATBUS-268 #2 / Ukraine): a new installation lands on a NAMED
# release, the same reasoning ops/setup-ubuntu-lts-24.sh's SSHDOERS_REF uses
# for the CI allowlist (architect ruling c3) — an install artifact procured
# from a moving ref cannot be named afterward, and a master-born box would
# refuse the very next scheduled upgrade as not-newer-than-installed. Checked
# locally, against this script's own clone, before anything on the remote box
# is touched — identity before content, same order the install timeline uses
# everywhere else.
git fetch --tags --quiet
if ! git rev-parse --verify --quiet "refs/tags/$VERSION" >/dev/null; then
    echo "Error: '$VERSION' is not a known tag in this repository."
    echo "List candidates with: ./sb upgrade check   (or: git tag -l 'v*' --sort=-version:refname)"
    exit 1
fi

# TARGET_ROLE (STATBUS-251, reshaped by STATBUS-254): a new country instance is
# an ordinary production slot — it follows releases on its own (STATBUS-248),
# never on a push.
#
# What this sets is now the box's ROLE, not its channel. The channel is DERIVED
# from the role on every `./sb config generate` (cli/internal/config/
# upgrade_role.go), so a value written here can no longer outlive the policy
# that set it — which is exactly what happened to five statistical offices'
# installations, which sat on the prerelease channel for two months because the
# channel was written once at creation and nothing recomputed it.
TARGET_ROLE=production

# The old interim branch here set the channel to prerelease when no stable
# release existed yet in the line. That is no longer a per-box setting to make:
# "what an ordinary installation follows" is one policy decision, answered in
# one table, for the whole fleet. A stable line exists today, so the branch was
# already dead — but the condition is still worth ANNOUNCING, because it tells
# the operator there may be nothing for this box to install yet.
git fetch --tags --quiet
if ! git tag -l 'v*' --sort=-version:refname | grep -qv -- '-rc\.'; then
    echo "NOTE: no stable release exists yet in this line. This instance is a production"
    echo "      installation and will follow the stable channel, so it will have nothing"
    echo "      to install until the first stable ships. That is the correct state, not a"
    echo "      misconfiguration — do not move the box to prerelease to work around it."
fi

# =============================================================================
# Operator config: which GitHub keys to authorize on this slot
# =============================================================================
#
# Two sources, both fetched via https://github.com/<source>.keys:
#   GITHUB_USERS       — personal keys for human SSH access (e.g. "jhf hhz")
#   GITHUB_DEPLOY_KEYS — repo public-key sources for CI access (e.g.
#                         "statisticsnorway/statbus" fetches that repo's
#                         registered deploy-key pubkeys into the box's
#                         authorized_keys)
#
# Persisted to ~/.create-new-statbus-installation.env so re-runs don't
# re-prompt. Either var can be overridden inline:
#     GITHUB_USERS="jhf hhz" GITHUB_DEPLOY_KEYS="statisticsnorway/statbus" \
#       ./create-new-statbus-installation.sh <slot> "<name>"
#
# Empty values are valid (no keys for that source).

OPERATOR_ENV="${HOME}/.create-new-statbus-installation.env"

# shellcheck source=/dev/null
[[ -f "$OPERATOR_ENV" ]] && source "$OPERATOR_ENV"

# Defaults if neither env nor config file has set them.
: "${GITHUB_USERS:=jhf hhz}"
: "${GITHUB_DEPLOY_KEYS:=statisticsnorway/statbus}"

# Interactive prompt if stdin is a tty and the values weren't pre-set
# (either from env or persisted config). Headless / CI runs use the
# defaults / pre-set values silently.
prompt_var() {
    local name="$1" desc="$2"
    local current="${!name}"
    echo ""
    echo "$desc"
    echo "  Current: ${current:-<empty>}"
    if [[ -t 0 ]]; then
        read -r -p "  New value (Enter to keep current): " new
        if [[ -n "$new" ]]; then
            eval "$name=\"\$new\""
        fi
    fi
}

if [[ -t 0 && ! -f "$OPERATOR_ENV" ]]; then
    echo "First run — choose which GitHub keys to authorize on $DEPLOYMENT_USER@$HOST."
    echo "Selection persists to $OPERATOR_ENV; subsequent runs skip these prompts."
    prompt_var GITHUB_USERS "GitHub usernames for human SSH access (space-separated):"
    prompt_var GITHUB_DEPLOY_KEYS "GitHub repo deploy-key sources for CI access (space-separated <org>/<repo>):"

    cat > "$OPERATOR_ENV" <<EOF
# create-new-statbus-installation.sh operator config
# Generated: $(date -Iseconds)
GITHUB_USERS="$GITHUB_USERS"
GITHUB_DEPLOY_KEYS="$GITHUB_DEPLOY_KEYS"
EOF
    chmod 600 "$OPERATOR_ENV"
    echo "Saved selection to $OPERATOR_ENV"
fi

echo "Authorizing on $DEPLOYMENT_USER@$HOST:"
echo "  GITHUB_USERS:       ${GITHUB_USERS:-<empty>}"
echo "  GITHUB_DEPLOY_KEYS: ${GITHUB_DEPLOY_KEYS:-<empty>}"
echo "  UPGRADE_ROLE:       $TARGET_ROLE"

# Verify DNS setup — apex record only. The api./www. subdomain split is dead:
# every real slot (dev/ug/ma) runs a single apex A/AAAA record, caddy/templates
# route by PATH (/rest) not by subdomain, and carry zero api./www. references.
echo "Verifying DNS setup..."
DNS_CHECK=$(dig +short "$DOMAIN")
if ! echo "$DNS_CHECK" | grep -q "$HOST"; then
    echo "Error: DNS record for $DOMAIN does not point to $HOST"
    echo "Expected to find $HOST in:"
    echo "$DNS_CHECK"
    exit 1
fi

echo "Configuring server..."

echo "Creating user"
ssh root@$HOST bash <<CREATE_USER
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    # Create user if doesn't exist
    if ! id "$DEPLOYMENT_USER" &>/dev/null; then
        echo "Creating user $DEPLOYMENT_USER..."
        adduser --gecos "Hosting for $DOMAIN" --disabled-password "$DEPLOYMENT_USER"
        adduser "$DEPLOYMENT_USER" docker
        echo "User created and added to docker group"
    else
        echo "User $DEPLOYMENT_USER already exists"
        if ! groups "$DEPLOYMENT_USER" | grep -q docker; then
            adduser "$DEPLOYMENT_USER" docker
            echo "Added existing user to docker group"
        fi
    fi
CREATE_USER

echo "Configuring SSH Access"
# Inline the same fetch+filter+dedupe contract used by ops/setup-ubuntu-lts-24.sh's
# populate_authorized_keys helper:
#   * ED25519-only filter (no RSA dead weight)
#   * Both source forms — `<user>.keys` and `<org>/<repo>.keys` — auto-detected
#     by presence of '/'
#   * Idempotent: existing keys preserved, no duplicates
# We pass GITHUB_USERS and GITHUB_DEPLOY_KEYS into the heredoc as plain
# variables; the remote script uses them directly.
ssh root@$HOST bash <<CONFIGURE_SSH_ACCESS
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    set -e

    target_user="$DEPLOYMENT_USER"
    users_list="$GITHUB_USERS"
    deploy_keys_list="$GITHUB_DEPLOY_KEYS"

    home_dir=\$(getent passwd "\$target_user" | cut -d: -f6)
    if [ -z "\$home_dir" ]; then
        echo "Error: user '\$target_user' has no home directory" >&2
        exit 1
    fi
    ssh_dir="\$home_dir/.ssh"
    auth_keys="\$ssh_dir/authorized_keys"
    stage_file="\$ssh_dir/.authorized_keys.stage.\$\$"

    mkdir -p "\$ssh_dir"
    chown "\$target_user:\$target_user" "\$ssh_dir"
    chmod 700 "\$ssh_dir"

    : > "\$stage_file"

    fetch_source() {
        local source="\$1" url keys key
        url="https://github.com/\${source}.keys"
        echo "Fetching ED25519 keys from \$url"
        keys=\$(curl -sL --fail "\$url" 2>/dev/null || true)
        if [ -z "\$keys" ]; then
            echo "Warning: no keys returned from \$url" >&2
            return 0
        fi
        while IFS= read -r key; do
            [ -z "\$key" ] && continue
            if [[ "\$key" =~ (^|[[:space:]])ssh-ed25519[[:space:]] ]]; then
                printf '%s # %s\n' "\$key" "\$url" >> "\$stage_file"
            fi
        done <<< "\$keys"
    }

    for s in \$users_list; do
        fetch_source "\$s"
    done
    for s in \$deploy_keys_list; do
        fetch_source "\$s"
    done

    if [ -s "\$auth_keys" ]; then
        cat "\$auth_keys" >> "\$stage_file"
    fi

    awk '
        {
            if (\$0 ~ /^[[:space:]]*\$/) next
            stripped = \$0
            sub(/^[[:space:]]*/, "", stripped)
            if (substr(stripped, 1, 1) == "#") next
            n = split(\$0, t, /[[:space:]]+/)
            algo_idx = 0
            for (i = 1; i <= n; i++) {
                if (t[i] ~ /^(ssh-|ecdsa-|sk-)/) { algo_idx = i; break }
            }
            if (algo_idx == 0 || algo_idx + 1 > n) next
            keybody = t[algo_idx] " " t[algo_idx + 1]
            if (!seen[keybody]++) print
        }
    ' "\$stage_file" > "\$auth_keys"
    rm -f "\$stage_file"

    chown "\$target_user:\$target_user" "\$auth_keys"
    chmod 600 "\$auth_keys"

    echo "Wrote \$(wc -l < "\$auth_keys") authorized key(s) for \$target_user"
CONFIGURE_SSH_ACCESS

echo "Clone StatBus repository..."
ssh $DEPLOYMENT_USER@$HOST bash <<CLONE_STATBUS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    # HTTPS, matching install.sh's own fresh-mode clone exactly (install.sh
    # :307-308) — statisticsnorway/statbus is public, so no deploy key is
    # needed. STATBUS-283: binary procurement, config generation, docker,
    # DB, and users all now delegate to install.sh below (one procurement
    # mechanism, one owner) — nothing on this box does SSH-authenticated git
    # any more, so the per-slot deploy-keygen step this used to require
    # (and the SSH clone it served) is gone, not just moved.
    if [ ! -d ~/statbus ]; then
        echo "Cloning StatBus repository at $VERSION..."
        git clone --depth 1 --branch "$VERSION" https://github.com/statisticsnorway/statbus.git ~/statbus
        git -C ~/statbus checkout -B current "$VERSION"
        echo "Repository cloned successfully"
    else
        echo "StatBus repository already exists"
        cd ~/statbus
        if ! git remote -v | grep -q 'statisticsnorway/statbus'; then
            echo "Error: Existing repository has incorrect remote"
            exit 1
        fi
        git fetch --tags --quiet
        git checkout -B current "$VERSION"
        echo "Checked out \$(git rev-parse --short HEAD) ($VERSION)"
    fi
CLONE_STATBUS

echo "Prepare users configuration..."
ssh $DEPLOYMENT_USER@$HOST bash <<CONFIGURE_USERS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    cd ~/statbus
    if [ ! -f .users.yml ]; then
        cp .users.example .users.yml
        echo "Created .users.yml from example"
    else
        echo "Users configuration already exists"
    fi

    # Check if .users.yml is identical to the example. This MUST run before
    # install.sh below: ./sb install's own step-table calls "sb users create"
    # internally, which hard-fails on a missing .users.yml but does not know
    # a copy-of-the-example is really a still-unedited placeholder.
    if cmp -s .users.yml .users.example; then
        echo "Error: .users.yml is identical to the example file."
        echo "Please edit ~/statbus/.users.yml to configure users before continuing."
        exit 1
    fi
CONFIGURE_USERS

echo "Find next available port offset"
PREV_MAX_OFFSET=$(ssh root@$HOST grep '^DEPLOYMENT_SLOT_PORT_OFFSET' /home/*/statbus/.env.config 2>/dev/null | grep -v "$DEPLOYMENT_USER" | sed 's/.*=\([0-9]*\)/\1/' | sort -n | tail -1)
OFFSET=$((PREV_MAX_OFFSET + 1))

echo "Write deployment-specific settings..."
# STATBUS-283: these are host-owned allocation decisions (offset, slot
# identity, role, URLs) — the product cannot know them (the offset is a fact
# about the other nine slots), so they are written here, not by install. They
# must land BEFORE install.sh runs: config generation (cli/internal/config/
# config.go:328-354, dotenv.Generate) is first-writer-wins from the FILE only
# — it never reads the process environment — so on a fresh clone .env.config
# does not exist yet and there is no other way to hand these values in. Using
# set_or_update (append if absent, update if wrong, no-op if already right)
# instead of the old sed-only form because sed can't create a missing line,
# and .env.config is genuinely missing on a first-ever run.
ssh $DEPLOYMENT_USER@$HOST bash << UPDATE_SETTINGS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    echo "Writing deployment-specific configuration..."
    cd ~/statbus
    touch .env.config

    set_or_update() {
        key="\$1"; value="\$2"
        if grep -q "^\${key}=" .env.config; then
            current=\$(grep "^\${key}=" .env.config | head -1 | cut -d'=' -f2-)
            if [ "\$current" != "\$value" ]; then
                sed -i "s#^\${key}=.*#\${key}=\${value}#" .env.config
                echo "Updated \$key to \$value"
            else
                echo "\$key is already \$value"
            fi
        else
            echo "\${key}=\${value}" >> .env.config
            echo "Set \$key to \$value"
        fi
    }

    set_or_update DEPLOYMENT_SLOT_PORT_OFFSET "$OFFSET"
    set_or_update DEPLOYMENT_SLOT_NAME "$DEPLOYMENT_SLOT_NAME"
    set_or_update DEPLOYMENT_SLOT_CODE "$DEPLOYMENT_SLOT_CODE"
    set_or_update CADDY_DEPLOYMENT_MODE private

    # Declare the box's upgrade ROLE (STATBUS-251, reshaped by STATBUS-254) —
    # OVERWRITE, not set-if-missing: a wrong value may already be present on a
    # retried run, and set-if-missing is the exact behaviour that let stale
    # values survive on five statistical offices' installations.
    #
    # UPGRADE_CHANNEL is NOT written here. It is derived from this role by
    # ./sb config generate (inside install.sh below); writing it into
    # .env.config directly would now be refused by that command, on purpose.
    set_or_update UPGRADE_ROLE "$TARGET_ROLE"

    # Apex domain only — the api./www. subdomain split is dead (see the
    # DNS-verification comment above for the evidence).
    set_or_update STATBUS_URL "https://$DOMAIN"
    set_or_update BROWSER_REST_URL "https://$DOMAIN"

    # Check and update API keys from statbus_dev if defaults are present
    current_seq_key=\$(grep '^SEQ_API_KEY=' .env.config | cut -d'=' -f2)
    if [ -z "\$current_seq_key" ] || [ "\$current_seq_key" = "secret_seq_api_key" ]; then
        dev_seq_key=\$(grep '^SEQ_API_KEY=' /home/statbus_dev/statbus/.env.config | cut -d'=' -f2)
        set_or_update SEQ_API_KEY "\$dev_seq_key"
        echo "Updated SEQ_API_KEY from statbus_dev"
    else
        echo "SEQ_API_KEY already configured with non-default value"
    fi

    current_slack_token=\$(grep '^SLACK_TOKEN=' .env.config | cut -d'=' -f2)
    if [ -z "\$current_slack_token" ] || [ "\$current_slack_token" = "secret_slack_api_token" ]; then
        dev_slack_token=\$(grep '^SLACK_TOKEN=' /home/statbus_dev/statbus/.env.config | cut -d'=' -f2)
        set_or_update SLACK_TOKEN "\$dev_slack_token"
        echo "Updated SLACK_TOKEN from statbus_dev"
    else
        echo "SLACK_TOKEN already configured with non-default value"
    fi
UPDATE_SETTINGS

# STATBUS-283: binary procurement, ./sb config generate, docker, DB creation,
# and ./sb users create all delegate to install.sh at the pinned version —
# one procurement mechanism, one owner, and its 9-state probe ladder makes a
# re-run an idempotent no-op instead of ./dev.sh create-db's old unconditional
# (and DESTRUCTIVE — AGENTS.md marks it local-dev-only) data wipe. .git
# already exists (cloned above), so install.sh takes its Rescue path: it
# re-fetches and re-checks-out the same version (harmless), places the
# binary, then runs ./sb install, which reads the .env.config we just wrote
# and fills in everything else around it.
#
# STATBUS-322: the trust flag MUST be threaded here, exactly as cloud.sh's
# install path threads it (trust_flag) — ./sb install's trusted-signer store
# is its own, not .env.config, and install.sh arrives via curl with no
# environment, so nothing implicit can supply it. Without the flag every
# newborn box dies at the deliberate no-default trusted-signers refusal
# (observed live at Malawi's birth). Resolution mirrors cloud.sh: the
# CLOUD_TRUST_KEY_USER env var first, else the value persisted on the box.
RESOLVED_TRUST_USER="${CLOUD_TRUST_KEY_USER:-}"
if [ -z "$RESOLVED_TRUST_USER" ]; then
    RESOLVED_TRUST_USER=$(ssh $DEPLOYMENT_USER@$HOST \
        "cd statbus && ./sb dotenv -f .env.config get TRUST_GITHUB_USER 2>/dev/null" || true)
fi
if [ -z "$RESOLVED_TRUST_USER" ]; then
    echo "Error: no trusted signer available for ./sb install." >&2
    echo "  Set CLOUD_TRUST_KEY_USER=<github-username> and re-run, e.g.:" >&2
    echo "  CLOUD_TRUST_KEY_USER=jhf ./cloud.sh create $DEPLOYMENT_SLOT_CODE ..." >&2
    exit 1
fi
echo "Installing StatBus (version $VERSION) via install.sh (trusted signer: $RESOLVED_TRUST_USER)..."
ssh $DEPLOYMENT_USER@$HOST bash <<INSTALL_STATBUS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    curl -fsSL https://statbus.org/install.sh | bash -s -- --version $VERSION --trust-github-user $RESOLVED_TRUST_USER
INSTALL_STATBUS

# Configure Caddy access permissions — BEFORE validate (architect ruling,
# STATBUS-283 part 2): Caddy reads the generated caddyfile as the caddy user,
# and a validate run before setfacl can fail on PERMISSIONS and be misread as
# a syntax error in a perfectly good config.
echo "Configure Caddy access permissions..."
ssh root@$HOST bash <<CONFIGURE_CADDY_ACCESS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    # Give Caddy access to the deployment user's home directory
    setfacl -m u:caddy:rx "/home/$DEPLOYMENT_USER"
    # Give Caddy access to the statbus directory
    setfacl -m u:caddy:rx "/home/$DEPLOYMENT_USER/statbus"
    # Give Caddy access to the caddy config directory
    setfacl -m u:caddy:rx "/home/$DEPLOYMENT_USER/statbus/caddy"
    setfacl -m u:caddy:rx "/home/$DEPLOYMENT_USER/statbus/caddy/config"
    # Give Caddy read access to the Caddyfile(s) within the config directory
    setfacl -m u:caddy:r "/home/$DEPLOYMENT_USER/statbus/caddy/config/"*.caddyfile
    echo "Configured Caddy access permissions"
CONFIGURE_CADDY_ACCESS

# Validate THEN reload the host Caddy — the LAST root-side step, FATAL on
# failure, never a warning (architect ruling, STATBUS-283 part 2, comment
# #1's evidence: Ukraine came up correct and unreachable — the slot caddyfile
# was wired and readable but the running host Caddy process had never been
# told to load it). Validate is blast-radius containment on a multi-tenant
# box: one malformed new-slot caddyfile, reloaded unvalidated, takes the
# proxy down for every country; validate-then-reload bounds the worst case to
# "the new slot stays unreachable" — exactly today's state — so this step
# cannot make things worse and can prevent a fleet outage. The failure must
# be fatal: an unreachable new slot that exits 0 is discovered by the
# country, not by us — precisely how Ukraine's gap surfaced.
echo "Validating and reloading host Caddy..."
ssh root@$HOST bash <<'RELOAD_CADDY'
    caddy validate --config /etc/caddy/Caddyfile || {
        echo "REFUSING TO RELOAD: host Caddy config is invalid with the new slot." >&2
        echo "The other slots are still served by the running process. Fix the" >&2
        echo "slot caddyfile, then re-run this script." >&2
        exit 1
    }
    systemctl reload caddy
RELOAD_CADDY

echo "Setup of ${DEPLOYMENT_SLOT_NAME}(${DEPLOYMENT_SLOT_CODE}) completed successfully!"
