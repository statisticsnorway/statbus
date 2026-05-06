#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e
# Print all commands if VERBOSE is defined
if [ -n "${VERBOSE}" ]; then
    set -x
fi

# This script creates a new StatBus installation on niue.statbus.org
# Usage: ./create-new-statbus-installation.sh <deployment_code> <deployment_name>
# Example: ./create-new-statbus-installation.sh jo "Jordan StatBus"

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <deployment_code> <deployment_name>"
    echo "Example: $0 jo \"Jordan StatBus\""
    exit 1
fi

DEPLOYMENT_SLOT_CODE="$1"
DEPLOYMENT_SLOT_NAME="$2"
DOMAIN="${DEPLOYMENT_SLOT_CODE}.statbus.org"
DEPLOYMENT_USER="statbus_${DEPLOYMENT_SLOT_CODE}"
HOST="niue.statbus.org"

# =============================================================================
# Operator config: which GitHub keys to authorize on this slot
# =============================================================================
#
# Two sources, both fetched via https://github.com/<source>.keys:
#   GITHUB_USERS       — personal keys for human SSH access (e.g. "jhf hhz")
#   GITHUB_DEPLOY_KEYS — repo deploy keys for CI access (e.g.
#                         "statisticsnorway/statbus" gives the deploy-to-*
#                         workflow ssh ability)
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

# Verify DNS setup
echo "Verifying DNS setup..."
for subdomain in "" "api." "www."; do
    RECORD="${subdomain}${DOMAIN}"
    DNS_CHECK=$(dig +short "$RECORD")
    if ! echo "$DNS_CHECK" | grep -q "$HOST"; then
        echo "Error: DNS record for $RECORD does not point to $HOST"
        echo "Expected to find $HOST in:"
        echo "$DNS_CHECK"
        exit 1
    fi
done

# Generate GitHub workflow file for deployment if it doesn't exist
if [ ! -f ".github/workflows/master-to-${DEPLOYMENT_SLOT_CODE}.yaml" ]; then
    echo "Generating GitHub workflow file..."
    if [ -f ".github/workflows/master-to-demo.yaml" ]; then
        mkdir -p .github/workflows
        sed "s/demo/${DEPLOYMENT_SLOT_CODE}/g" .github/workflows/master-to-demo.yaml > ".github/workflows/master-to-${DEPLOYMENT_SLOT_CODE}.yaml"
        echo "Created GitHub workflow file for ${DEPLOYMENT_SLOT_CODE}"
    else
        echo "Warning: Could not find template workflow file .github/workflows/master-to-demo.yaml"
    fi
else
    echo "GitHub workflow file for ${DEPLOYMENT_SLOT_CODE} already exists"
fi

# Generate deploy-to workflow file if it doesn't exist
if [ ! -f ".github/workflows/deploy-to-${DEPLOYMENT_SLOT_CODE}.yaml" ]; then
    echo "Generating deploy-to workflow file..."
    if [ -f ".github/workflows/deploy-to-demo.yaml" ]; then
        mkdir -p .github/workflows
        sed "s/demo/${DEPLOYMENT_SLOT_CODE}/g" .github/workflows/deploy-to-demo.yaml > ".github/workflows/deploy-to-${DEPLOYMENT_SLOT_CODE}.yaml"
        echo "Created deploy-to workflow file for ${DEPLOYMENT_SLOT_CODE}"
    else
        echo "Warning: Could not find template workflow file .github/workflows/deploy-to-demo.yaml"
    fi
else
    echo "Deploy-to workflow file for ${DEPLOYMENT_SLOT_CODE} already exists"
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
        adduser --gecos "Hosting for www.$DOMAIN and api.$DOMAIN" --disabled-password "$DEPLOYMENT_USER"
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

echo "Configuring github deployment with ssh"
ssh $DEPLOYMENT_USER@$HOST bash <<GITHUB_DEPLOYMENT_ACCESS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    # Generate SSH key for the user, to be added to github as a deployment key.
    if [ ! -f "\$HOME/.ssh/id_ed25519" ]; then
        ssh-keygen -t ed25519 -f "~/.ssh/id_ed25519" -N "" -C "$DEPLOYMENT_USER@\$(hostname --fqdn)"
    else
        echo "SSH deployment key already exists and will be preserved"
    fi

    # Print the public key for GitHub deployment
    echo "Public key for GitHub deployment (add to https://github.com/statisticsnorway/statbus/settings/keys):"
    cat ~/.ssh/id_ed25519.pub
GITHUB_DEPLOYMENT_ACCESS

echo "Clone StatBus repository..."
ssh $DEPLOYMENT_USER@$HOST bash <<CLONE_STATBUS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    # Ensure GitHub's host key is known
    if ! grep -q "github.com" ~/.ssh/known_hosts; then
        ssh-keyscan github.com >> ~/.ssh/known_hosts
    else
        echo "GitHub's host key is already known"
    fi

    if [ ! -d ~/statbus ]; then
        echo "Cloning StatBus repository..."
        if ! git clone git@github.com:statisticsnorway/statbus.git ~/statbus; then
            echo "Error: Failed to clone StatBus repository. Please ensure deployment key is set up correctly."
            exit 1
        fi
        echo "Repository cloned successfully"
    else
        echo "StatBus repository already exists"
        # Verify git remote
        if ! cd ~/statbus && git remote -v | grep -q 'statisticsnorway/statbus'; then
            echo "Error: Existing repository has incorrect remote"
            exit 1
        fi
    fi
CLONE_STATBUS

echo "Configure StatBus..."
ssh $DEPLOYMENT_USER@$HOST bash <<CONFIGURE_STATBUS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    echo "Generating configuration files..."
    if [ ! -f ~/statbus/.env ]; then
        cd ~/statbus && ./sb config generate
        echo "Generated .env configuration"
    else
        echo "Configuration .env already exists"
    fi

    if [ ! -f ~/statbus/.users.yml ]; then
        cd ~/statbus && cp .users.example .users.yml
        echo "Created .users.yml from example"
    else
        echo "Users configuration already exists"
    fi

    # Check if .users.yml is identical to the example
    if cmp -s ~/statbus/.users.yml ~/statbus/.users.example; then
        echo "Error: .users.yml is identical to the example file."
        echo "Please edit ~/statbus/.users.yml to configure users before continuing."
        exit 1
    fi
CONFIGURE_STATBUS


echo "Find next available port offset"
PREV_MAX_OFFSET=$(ssh root@$HOST grep '^DEPLOYMENT_SLOT_PORT_OFFSET' /home/*/statbus/.env.config 2>/dev/null | grep -v "$DEPLOYMENT_USER" | sed 's/.*=\([0-9]*\)/\1/' | sort -n | tail -1)
OFFSET=$((PREV_MAX_OFFSET + 1))

echo "Update deployment-specific settings..."
ssh $DEPLOYMENT_USER@$HOST bash << UPDATE_SETTINGS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    echo "Updating deployment-specific configuration..."
    cd ~/statbus

    # Only update port offset if different
    current_offset=\$(grep '^DEPLOYMENT_SLOT_PORT_OFFSET=' .env.config | cut -d'=' -f2)
    if [ "\$current_offset" != "$OFFSET" ]; then
        sed -i "s/DEPLOYMENT_SLOT_PORT_OFFSET=.*/DEPLOYMENT_SLOT_PORT_OFFSET=$OFFSET/" .env.config
        echo "Updated port offset to $OFFSET"
    else
        echo "Port offset is already $OFFSET"
    fi

    # Only update slot name if different
    current_name=\$(grep '^DEPLOYMENT_SLOT_NAME=' .env.config | cut -d'=' -f2)
    if [ "\$current_name" != "$DEPLOYMENT_SLOT_NAME" ]; then
        sed -i "s/DEPLOYMENT_SLOT_NAME=.*/DEPLOYMENT_SLOT_NAME=$DEPLOYMENT_SLOT_NAME/" .env.config
        echo "Updated slot name to $DEPLOYMENT_SLOT_NAME"
    else
        echo "Slot name is already $DEPLOYMENT_SLOT_NAME"
    fi

    # Update CADDY_DEPLOYMENT_MODE
    current_caddy_mode=\$(grep '^CADDY_DEPLOYMENT_MODE=' .env.config | cut -d'=' -f2)
    if [ "\$current_caddy_mode" = "development" ]; then
        sed -i "s/CADDY_DEPLOYMENT_MODE=development/CADDY_DEPLOYMENT_MODE=private/" .env.config
        echo "Updated CADDY_DEPLOYMENT_MODE to private"
    elif [ "\$current_caddy_mode" != "private" ]; then
        # If it's neither development nor private, it might be an unexpected value.
        # For now, we'll assume if it's not development, it's either already private or set to something else intentionally.
        # If you want to force it to private regardless of current value (unless already private), adjust logic here.
        echo "CADDY_DEPLOYMENT_MODE is '\$current_caddy_mode', not changing."
    else
        echo "CADDY_DEPLOYMENT_MODE is already private"
    fi
    
    # Only update slot code if different
    current_code=\$(grep '^DEPLOYMENT_SLOT_CODE=' .env.config | cut -d'=' -f2)
    if [ "\$current_code" != "$DEPLOYMENT_SLOT_CODE" ]; then
        sed -i "s/DEPLOYMENT_SLOT_CODE=.*/DEPLOYMENT_SLOT_CODE=$DEPLOYMENT_SLOT_CODE/" .env.config
        echo "Updated slot code to $DEPLOYMENT_SLOT_CODE"
    else
        echo "Slot code is already $DEPLOYMENT_SLOT_CODE"
    fi

    # Only update URLs if different
    current_statbus_url=\$(grep '^STATBUS_URL=' .env.config | cut -d'=' -f2)
    if [ "\$current_statbus_url" != "https://www.$DOMAIN" ]; then
        sed -i "s#STATBUS_URL=.*#STATBUS_URL=https://www.$DOMAIN#" .env.config
        echo "Updated StatBus URL"
    else
        echo "StatBus URL is already https://www.$DOMAIN"
    fi

    current_supabase_url=\$(grep '^BROWSER_REST_URL=' .env.config | cut -d'=' -f2)
    if [ "\$current_supabase_url" != "https://api.$DOMAIN" ]; then
        sed -i "s#BROWSER_REST_URL=.*#BROWSER_REST_URL=https://api.$DOMAIN#" .env.config
        echo "Updated Supabase URL"
    else
        echo "Supabase URL is already https://api.$DOMAIN"
    fi

    # Add GitHub deployment key if not already present
    DEPLOY_KEY='command="/usr/local/bin/deploy-statbus.sh" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAdpqAWRoDDKDa7neWpTLe+coEYYSkhzw2znSJ3E6XjD https://github.com/statisticsnorway/statbus'
    if ! grep -q "deploy-statbus.sh.*statisticsnorway/statbus" ~/.ssh/authorized_keys; then
        echo "\$DEPLOY_KEY" >> ~/.ssh/authorized_keys
        echo "Added GitHub deployment key"
    else
        echo "GitHub deployment key already exists"
    fi

    # Check and update API keys from statbus_dev if defaults are present
    current_seq_key=\$(grep '^SEQ_API_KEY=' .env.config | cut -d'=' -f2)
    if [ "\$current_seq_key" = "secret_seq_api_key" ]; then
        dev_seq_key=\$(grep '^SEQ_API_KEY=' /home/statbus_dev/statbus/.env.config | cut -d'=' -f2)
        sed -i "s#SEQ_API_KEY=.*#SEQ_API_KEY=\$dev_seq_key#" .env.config
        echo "Updated SEQ_API_KEY from statbus_dev"
    else
        echo "SEQ_API_KEY already configured with non-default value"
    fi

    current_slack_token=\$(grep '^SLACK_TOKEN=' .env.config | cut -d'=' -f2)
    if [ "\$current_slack_token" = "secret_slack_api_token" ]; then
        dev_slack_token=\$(grep '^SLACK_TOKEN=' /home/statbus_dev/statbus/.env.config | cut -d'=' -f2)
        sed -i "s#SLACK_TOKEN=.*#SLACK_TOKEN=\$dev_slack_token#" .env.config
        echo "Updated SLACK_TOKEN from statbus_dev"
    else
        echo "SLACK_TOKEN already configured with non-default value"
    fi
UPDATE_SETTINGS


# Regenerate configuration with updated settings
ssh $DEPLOYMENT_USER@$HOST bash <<USE_ADAPTED_CONFIG
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    cd ~/statbus && ./sb config generate
    echo "Generated .env configuration with updated settings"
USE_ADAPTED_CONFIG

# Configure Caddy access permissions
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

echo "Starting StatBus services..."
ssh $DEPLOYMENT_USER@$HOST bash <<START_STATBUS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    cd ~/statbus
    ./sb start all
    # Include the paths for building crystal installed with homebrew.
    source /etc/profile.d/homebrew.sh
    ./dev.sh create-db
    ./sb users create
START_STATBUS

echo "Setup of ${DEPLOYMENT_SLOT_NAME}(${DEPLOYMENT_SLOT_CODE}) completed successfully!"
