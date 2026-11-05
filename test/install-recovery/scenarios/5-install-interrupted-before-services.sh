#!/usr/bin/env bash
# STATBUS-572: interrupt a genuine first install BEFORE any container exists
# (the manual box, rc.09: Ctrl-C during Images). The install leaves its own
# marker and no process; the same command run again must continue the install,
# never classify it as an interrupted upgrade or send the operator elsewhere.
# Requires a tagged candidate and a paid VM. Never synthesize the install markers.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-5-install-interrupted-before-services}"
HARNESS_DEPLOYMENT_MODE=standalone
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[ "$TARGET_SHA" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] || { echo 'candidate tag must point at HEAD' >&2; exit 1; }
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
IP=$(_hcloud_server_ip "$VM_NAME")
_wait_for_ssh "$IP" 30
scp -O "${SSH_OPTS[@]}" "$REPO_ROOT/install.sh" root@"$IP":/tmp/statbus-install.sh
VM_ROOT_EXEC chmod 0644 /tmp/statbus-install.sh

# Run the actual fresh installer. The watcher interrupts at the Images RUNNING
# output boundary, as the operator's Ctrl-C did. A missed boundary fails the fixture rather than pretending
# that a completed install was interrupted.
VM_SCRIPT_INLINE interrupt-before-services-launch "$INSTALL_TARGET_TAG" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
version="$1"
( umask 077; cat > "$HOME/install-input.env" <<'CONFIG'
CADDY_DEPLOYMENT_MODE=standalone
SITE_DOMAIN=statbus-test.local
TLS_CERT_FILE=/data/custom-certs/domain.crt
TLS_KEY_FILE=/data/custom-certs/domain.key
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
TRUST_GITHUB_USER=jhf
CONFIG
)
# A job started with & from this non-interactive shell inherits SIGINT as
# ignored, and bash cannot reset a signal ignored on entry. sb then survived
# the interrupt while docker compose died, so rc.11 saw an image-pull failure
# instead of a Ctrl-C. perl restores the default the operator's terminal gives.
setsid perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV or die "exec: $!"' bash -c 'cd "$HOME"; export STATBUS_ENV_CONFIG="$HOME/install-input.env" STATBUS_USERS_FILE=/tmp/users.yml STATBUS_INSTALL_VERSION="$1" STATBUS_MIN_DISK_GB=5 STATBUS_HARNESS_CERT_STAGING="$HOME/harness-certs"; bash /tmp/statbus-install.sh --non-interactive' bash "$version" > "$HOME/first-install.log" 2>&1 &
echo $! > "$HOME/first-install.pid"
REMOTE
harness_register_log interrupt-before-services /home/statbus/first-install.log "$IP"
VM_SCRIPT_INLINE interrupt-before-services-watch <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
pid=$(cat "$HOME/first-install.pid")
observed=0
for ((attempt=0; attempt<2400; attempt++)); do
    if grep -Eq '^\[[0-9]+/[0-9]+\] Images +RUNNING' "$HOME/first-install.log"; then
        observed=1
        kill -INT -- "-$pid" 2>/dev/null || true
        break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
done
wait "$pid" 2>/dev/null || true
[ "$observed" = 1 ] || { cat "$HOME/first-install.log" >&2; echo 'Images boundary not observed' >&2; exit 1; }
cd "$HOME/statbus"
test -f .env.config
test -f .env.credentials
# The interruption left the install's own marker and no live holder, and no
# StatBus container was ever created.
grep -q '"holder": *"install"' tmp/upgrade-in-progress.json
[ -z "$(docker ps -aq --filter label=com.docker.compose.project)" ]
REMOTE

RERUN_LOG=$(mktemp)
VM_EXEC bash -c "cd ~ && export STATBUS_ENV_CONFIG=\"\$HOME/install-input.env\" STATBUS_USERS_FILE=/tmp/users.yml STATBUS_INSTALL_VERSION='$INSTALL_TARGET_TAG' STATBUS_MIN_DISK_GB=5; unset STATBUS_HARNESS_CERT_STAGING; bash /tmp/statbus-install.sh --non-interactive" >"$RERUN_LOG" 2>&1 || { cat "$RERUN_LOG" >&2; exit 1; }
grep -Fq 'The previous install was interrupted; continuing it.' "$RERUN_LOG" || { cat "$RERUN_LOG" >&2; exit 1; }
if grep -Eq 'proxy\) container was removed|Recovering an interrupted upgrade|Outside fix' "$RERUN_LOG"; then cat "$RERUN_LOG" >&2; exit 1; fi
grep -Eq '^\[[0-9]+/[0-9]+\] Services +DONE' "$RERUN_LOG" || { cat "$RERUN_LOG" >&2; exit 1; }
grep -Eq '^\[[0-9]+/[0-9]+\] (Seed|Migrations) +DONE' "$RERUN_LOG" || { cat "$RERUN_LOG" >&2; exit 1; }
VM_EXEC bash -c 'cd ~/statbus && test ! -e .first-install-signer-pending && ./sb psql -X -t -A -c "SELECT to_regclass('\''public.upgrade'\'') IS NOT NULL" | grep -qx t'
assert_health_passes "$VM_NAME"
VM_EXEC bash -c 'cd ~/statbus && docker compose --profile all ps --status running --format "{{.Service}}"' | sort > "$RERUN_LOG.services"
for service in app db proxy rest worker; do
    grep -qx "$service" "$RERUN_LOG.services" || { echo "missing running service: $service" >&2; exit 1; }
done
echo 'PASS: a first install interrupted before any container existed was continued by the same command to serving web/API'
