#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$REPO_ROOT/ops/release/verify-public-image.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/docker" <<'FAKE_DOCKER'
#!/bin/bash
set -euo pipefail
ref="${@: -1}"
mode=authenticated
[ -n "${DOCKER_CONFIG:-}" ] && mode=anonymous
echo "$mode $ref" >> "$FAKE_DOCKER_LOG"
if [ "$mode" = anonymous ] && [ "${FAKE_ANON_DENY:-0}" = 1 ]; then
    echo "denied: requested access to the resource is denied (HTTP 403)" >&2
    exit 1
fi
if [ "$mode" = anonymous ]; then
    digest="${FAKE_DEST_DIGEST:-sha256:same}"
else
    digest="${FAKE_SOURCE_DIGEST:-sha256:same}"
fi
printf 'Name: %s\nMediaType: application/vnd.oci.image.index.v1+json\nDigest: %s\n' "$ref" "$digest"
FAKE_DOCKER
chmod +x "$tmpdir/docker"
export PATH="$tmpdir:$PATH"
export FAKE_DOCKER_LOG="$tmpdir/docker.log"
export PUBLIC_IMAGE_VERIFY_ATTEMPTS=1

assert_contains() {
    local file="$1" text="$2" name="$3"
    if ! grep -F "$text" "$file" >/dev/null; then
        echo "FAIL: $name: '$text' not found in $file" >&2
        cat "$file" >&2
        exit 1
    fi
    echo "PASS: $name"
}

: > "$FAKE_DOCKER_LOG"
FAKE_SOURCE_DIGEST=sha256:abc FAKE_DEST_DIGEST=sha256:abc \
    "$VERIFY" ghcr.io/org/statbus-sb:parent ghcr.io/org/statbus-sb:target \
    >"$tmpdir/pass.out" 2>&1
assert_contains "$FAKE_DOCKER_LOG" "authenticated ghcr.io/org/statbus-sb:parent" "source inspected with workflow credentials"
assert_contains "$FAKE_DOCKER_LOG" "anonymous ghcr.io/org/statbus-sb:target" "destination inspected anonymously"
assert_contains "$tmpdir/pass.out" "index digest matches source: sha256:abc" "matching retag digest passes"

if FAKE_SOURCE_DIGEST=sha256:source FAKE_DEST_DIGEST=sha256:destination \
    "$VERIFY" ghcr.io/org/statbus-sb:parent ghcr.io/org/statbus-sb:target \
    >"$tmpdir/mismatch.out" 2>&1
then
    echo "FAIL: digest mismatch unexpectedly passed" >&2
    exit 1
fi
assert_contains "$tmpdir/mismatch.out" "image index digest mismatch" "retag digest mismatch fails"

if FAKE_ANON_DENY=1 "$VERIFY" \
    ghcr.io/statisticsnorway/statbus-sb:parent \
    ghcr.io/statisticsnorway/statbus-sb:target \
    >"$tmpdir/private.out" 2>&1
then
    echo "FAIL: anonymously denied package unexpectedly passed" >&2
    exit 1
fi
assert_contains "$tmpdir/private.out" "not anonymously deployable [auth]" "private destination names auth class"
assert_contains "$tmpdir/private.out" "Package settings -> Change visibility -> Public" "private package names settings remedy"

echo "verify-public-image tests: PASS"
