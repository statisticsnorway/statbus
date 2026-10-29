#!/usr/bin/env bash
# Every workflow step that logs docker in to ghcr.io survives transient
# login failures and still fails when the registry never answers.
#
# One resolver timeout on the first ghcr.io lookup failed a whole per-commit
# image build, and the upgrade arcs waited 40 minutes for an image that was
# never pushed (v2026.10.5-rc.02, Images run 40967128256). This runs the REAL
# run: text of each such step (extracted with yq) against a fake docker that
# fails the first N logins; sleep is stubbed. No network or registry is used.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v yq >/dev/null || { echo "FAIL: yq is required" >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ghcr-login-retry.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
[ "$1" = login ] || exit 0
n=$(( $(cat "$FAKE_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_DIR/calls"
cat > "$FAKE_DIR/stdin"
[ "$n" -gt "$FAKE_FAILURES" ]
EOF
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sleep"
chmod +x "$TMP/bin/docker" "$TMP/bin/sleep"

steps=0
for wf in images release fast-tests upgrade-arc-harness; do
    file="$ROOT/.github/workflows/$wf.yaml"
    count=$(yq '[.jobs[].steps[] | select(.run != null and (.run | test("docker login")))] | length' "$file")
    for i in $(seq 0 $((count - 1))); do
        yq "[.jobs[].steps[] | select(.run != null and (.run | test(\"docker login\")))][$i].run" "$file" > "$TMP/step.sh"
        name=$(yq "[.jobs[].steps[] | select(.run != null and (.run | test(\"docker login\")))][$i] | (.name // .id // \"unnamed\")" "$file")
        # Only the login itself is under test: take the retry loop that holds
        # the docker login (its `for attempt` line through its `done`), so the
        # rest of the step's registry work is not executed.
        awk '/for attempt/ {buf=""; inloop=1} inloop {buf=buf $0 "\n"} inloop && /docker login/ {hit=1} inloop && /^ *done$/ {if (hit) {printf "%s", buf; exit} inloop=0}' "$TMP/step.sh" > "$TMP/login.sh"
        [ -s "$TMP/login.sh" ] || {
            # The off-master arc base check runs only for a base outside
            # master's ancestry and fails with the login error itself.
            if grep -q 'Arc base registry login failed' "$TMP/step.sh"; then continue; fi
            echo "FAIL: $wf.yaml step '$name' logs in to ghcr.io without retrying" >&2; exit 1; }
        for failures in 2 5; do
            rm -f "$TMP/calls"
            rc=0
            PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_FAILURES=$failures REGISTRY=ghcr.io \
                GHCR_USER=bot GHCR_TOKEN=tok GH_TOKEN=tok ACTOR=bot \
                bash -e "$TMP/login.sh" >/dev/null 2>&1 || rc=$?
            calls=$(cat "$TMP/calls")
            if [ "$failures" = 2 ]; then
                [ "$rc" = 0 ] && [ "$calls" = 3 ] || { echo "FAIL: $wf.yaml '$name': 2 transient failures gave rc=$rc after $calls logins" >&2; exit 1; }
                [ "$(cat "$TMP/stdin")" = tok ] || { echo "FAIL: $wf.yaml '$name': token not on stdin" >&2; exit 1; }
            else
                [ "$rc" != 0 ] && [ "$calls" = 5 ] || { echo "FAIL: $wf.yaml '$name': permanent failure gave rc=$rc after $calls logins" >&2; exit 1; }
            fi
        done
        steps=$((steps + 1))
        echo "PASS: $wf.yaml '$name' logs in after 2 transient failures and fails after 5"
    done
    if rg -q 'docker/login-action' "$file"; then
        echo "FAIL: $wf.yaml still uses docker/login-action, which does not retry" >&2; exit 1
    fi
done
[ "$steps" -ge 9 ] || { echo "FAIL: expected at least 9 ghcr login steps, found $steps" >&2; exit 1; }
echo "ghcr login retry: PASS ($steps steps)"
