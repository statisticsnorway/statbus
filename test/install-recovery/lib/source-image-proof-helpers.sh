#!/usr/bin/env bash
# Shared source-proof boundaries, extracted so offline controls exercise the
# same assertions and actual cloud handler as the guest scenario.
# shellcheck disable=SC1091,SC2034,SC2329 # Sourced cloud handler consumes these globals and SSH override.
source_proof_assert_identity() {
    local artifact=$1 metadata=$2 sha=$3 tag=$4 headers=$5
    printf '%s\n' "$headers" | grep -Eiq '^cache-control:.*no-store' || {
        echo 'serving artifact lacks Cache-Control: no-store' >&2; return 1;
    }
    printf '%s\n' "$artifact" | jq -e --arg sha "$sha" \
        '.commit_sha | type == "string" and test("^[0-9a-f]{40}$") and . == $sha' >/dev/null || return 1
    printf '%s\n' "$metadata" | jq -e --arg sha "$sha" --arg tag "$tag" \
        'type == "array" and length == 1 and .[0].commit_sha == $sha and .[0].resolved_name == $tag and .[0].release_status == "prerelease" and .[0].build_name == $tag' >/dev/null
}

source_proof_assert_callbacks() {
    local events=$1 tag=$2 short=$3 old=$4 old_short=$5 path=$6 event
    case "$path" in operator) event=install_completed ;; scheduled) event=completed ;; *) return 2 ;; esac
    printf '%s\n' "$events" | awk -F '|' -v event="$event" -v tag="$tag" -v short="$short" \
        '$1 == event && ($2 == tag || $2 == short) {found=1} END {exit !found}' || {
        echo "missing legitimate candidate $event callback" >&2; return 1;
    }
    printf '%s\n' "$events" | awk -F '|' -v old="$old" -v short="$old_short" \
        '($1 == "completed" || $1 == "install_completed") && ($2 == old || $2 == short) {bad=1} END {exit bad}' || {
        echo 'old target emitted a success callback' >&2; return 1;
    }
}

source_proof_serving_identity() {
    local response artifact headers metadata
    response=$(VM_SCRIPT_INLINE serving-app-identity <<'REMOTE'
set -euo pipefail
cd ~/statbus
port=$(./sb dotenv -f .env get CADDY_HTTP_PORT)
host=$(./sb dotenv -f .env.config get SITE_DOMAIN)
headers=$(mktemp)
curl --fail --silent --show-error --max-time 30 -H "Host: $host" -H 'Cache-Control: no-store' -D "$headers" "http://127.0.0.1:$port/_statbus-build.json"
printf '\nSTATBUS-PROOF-HEADERS\n'
cat "$headers"
rm -f "$headers"
REMOTE
    ) || return
    artifact=${response%%$'\nSTATBUS-PROOF-HEADERS\n'*}
    headers=${response#*$'\nSTATBUS-PROOF-HEADERS\n'}
    metadata=$(VM_SCRIPT_INLINE serving-release-identity "$TARGET_SHA" <<'REMOTE'
set -euo pipefail
cd ~/statbus
port=$(./sb dotenv -f .env get CADDY_HTTP_PORT)
host=$(./sb dotenv -f .env.config get SITE_DOMAIN)
curl --fail --silent --show-error --max-time 30 -H "Host: $host" -H 'Cache-Control: no-store' "http://127.0.0.1:$port/rest/rpc/release_identity?p_commit_sha=$1"
REMOTE
    ) || return
    printf 'serving artifact: %s\nserving metadata: %s\n%s\n' "$artifact" "$metadata" "$headers"
    source_proof_assert_identity "$artifact" "$metadata" "$TARGET_SHA" "$INSTALL_TARGET_TAG" "$headers"
}

# The host verifier is the named candidate's published executable, not a copied
# verify recipe or a fixture. Only the SSH carrier is adapted to the owned guest.
source_proof_operator_install() (
    local host_dir arch rc=0
    host_dir=$(mktemp -d "${TMPDIR:-/tmp}/statbus-proof-host.XXXXXX")
    trap 'rm -rf "$host_dir"' EXIT
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) arch=linux-amd64 ;;
        Linux/aarch64) arch=linux-arm64 ;;
        Darwin/arm64) arch=darwin-arm64 ;;
        *) echo 'unsupported host for candidate artifact verifier' >&2; exit 1 ;;
    esac
    curl -fsSL --retry 3 "https://github.com/statisticsnorway/statbus/releases/download/$INSTALL_TARGET_TAG/sb-$arch" -o "$host_dir/sb"
    chmod 0755 "$host_dir/sb"
    "$host_dir/sb" --version | grep -F "$TARGET_SHORT" >/dev/null || exit 1
    STATBUS_CLOUD_LIB_ONLY=1 source "$REPO_ROOT/cloud.sh"
    FLEET_REGISTRY=("proof|cloud|statbus@$VM_IP|${HARNESS_SITE_DOMAIN:-statbus-test.local}|anon")
    FLEET_TRUST_KEY_USER=jhf
    SCRIPT_DIR=$host_dir
    INSTALL_URL=file:///tmp/statbus-install.sh
    ssh_transport() {
        [ "$1" = "statbus@$VM_IP" ] || { echo 'REFUSE transport outside owned guest' >&2; return 2; }
        shift
        [ "$#" = 1 ] || return 2
        VM_EXEC bash -c "$1"
    }
    cmd_install proof "$INSTALL_TARGET_TAG" >"$INSTALL_LOG" 2>&1 || rc=$?
    cat "$INSTALL_LOG"
    exit "$rc"
)
