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
ssh root@$HOST bash <<CONFIGURE_SSH_ACCESS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    # Configure GitHub users' SSH access
    echo "Configuring GitHub users SSH access..."
    GITHUB_USERS=("jhf" "hhz")

    # Add GitHub users' SSH keys
    for gh_user in "\${GITHUB_USERS[@]}"; do
        # Create .ssh directory if it doesn't exist
        sudo -i -u "$DEPLOYMENT_USER" bash -c 'mkdir -p "\$HOME/.ssh"'

        # Extract the key
        KEY=\$(curl -sL "https://github.com/\$gh_user.keys" | grep ed25519 | head -n1)

        if [ -n "\$KEY" ]; then
            # Check if key already exists
            if ! sudo -i -u "$DEPLOYMENT_USER" bash -c "grep -q \"\$KEY\" \"\\\$HOME/.ssh/authorized_keys\"" 2>/dev/null; then
                # Add the key with comment
                echo "\$KEY # https://github.com/\$gh_user.keys" | sudo -i -u "$DEPLOYMENT_USER" bash -c 'cat >> "\$HOME/.ssh/authorized_keys"'
                echo "Added SSH key for GitHub user \$gh_user"
            else
                echo "SSH key for GitHub user \$gh_user already exists"
            fi
        fi
        # Set proper permissions on SSH directory and files
        sudo -i -u "$DEPLOYMENT_USER" bash -c 'chmod 700 "\$HOME/.ssh" && chmod 600 "\$HOME/.ssh/authorized_keys"'
    done
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
        cd ~/statbus && ./devops/manage-statbus.sh generate-config
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
    cd ~/statbus && ./devops/manage-statbus.sh generate-config
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
    # Give Caddy read access to the deployment config file
    setfacl -m u:caddy:r "/home/$DEPLOYMENT_USER/statbus/deployment.caddyfile"
    echo "Configured Caddy access permissions"
CONFIGURE_CADDY_ACCESS

echo "Starting StatBus services..."
ssh $DEPLOYMENT_USER@$HOST bash <<START_STATBUS
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    cd ~/statbus
    ./devops/manage-statbus.sh start required
    ./devops/manage-statbus.sh activate_sql_saga
    # Include the paths for building crystal installed with homebrew.
    source /etc/profile.d/homebrew.sh
    ./devops/manage-statbus.sh create-db-structure
    ./devops/manage-statbus.sh create-users
START_STATBUS

echo "Setup of ${DEPLOYMENT_SLOT_NAME}(${DEPLOYMENT_SLOT_CODE}) completed successfully!"
