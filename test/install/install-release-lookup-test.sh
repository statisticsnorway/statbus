#!/usr/bin/env bash
# STATBUS-582: install.sh finds the release to install even when GitHub's
# release list (the API) does not answer, and says what failed when nothing
# answers. Found by the rc.14 gate (2026-11-06, run 42240573107): every
# anonymous /releases API call answered 504 for over 20 minutes while
# /releases/latest and the releases feed answered, and install.sh printed
# "Error: No pre-release published." with rc.14 published.
#
# The double stands in for curl -f: a failing source exits 22 like curl does
# on a 5xx. It answers the release list ($RELEASES_API), /releases/latest
# ($LATEST_API) and the releases feed ($RELEASES_FEED), and stops the run
# once the version is resolved (the clone is the next network step), so the
# test observes only which version install.sh chose and what it said.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/install-release-lookup.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home"
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url=$arg ;; esac; done
case "$url" in
    https://api.github.com/repos/statisticsnorway/statbus/releases\?per_page=50)
        echo list >> "$CALLS"
        [ "${RELEASES_API:-ok}" = ok ] || exit 22
        printf '[{"tag_name": "v2026.11.1-rc.14"}, {"tag_name": "v2026.11.0"}, {"tag_name": "v2026.11.1-rc.13"}]\n' ;;
    https://api.github.com/repos/statisticsnorway/statbus/releases/latest)
        echo latest >> "$CALLS"
        [ "${LATEST_API:-ok}" = ok ] || exit 22
        printf '{"tag_name": "v2026.11.0"}\n' ;;
    https://github.com/statisticsnorway/statbus/releases.atom)
        [ "${RELEASES_FEED:-ok}" = ok ] || exit 22
        for tag in v2026.11.1-rc.14 v2026.11.0 v2026.11.1-rc.13; do
            printf '  <link rel="alternate" type="text/html" href="https://github.com/statisticsnorway/statbus/releases/tag/%s"/>\n' "$tag"
        done ;;
    https://github.com/statisticsnorway/statbus/releases/latest)
        # Like the real page: a redirect to releases/tag/<stable>, which
        # curl -L -o /dev/null -w '%{url_effective}' reports as the final URL.
        echo latest-page >> "$CALLS"
        [ "${RELEASES_FEED:-ok}" = ok ] || exit 22
        case " $* " in
            *" -w "*) printf 'https://github.com/statisticsnorway/statbus/releases/tag/v2026.11.0\n' ;;
            *) printf '<html>release page for v2026.11.0</html>\n' ;;
        esac ;;
    https://github.com/statisticsnorway/statbus/releases/download/*)
        # The version is resolved; the next step downloads it. Stop the whole
        # run here so the test sees only the lookup.
        echo "STOP-AT-DOWNLOAD $url" >&2
        kill -TERM "$PPID" 2>/dev/null
        exit 22 ;;
    *) echo "curl double: unexpected $url" >&2; exit 22 ;;
esac
EOF
# The version is resolved before the clone; the double stops the run there.
cat > "$work/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "STOP-AT-GIT $*" >&2
exit 97
EOF
cat > "$work/bin/docker" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = info ] && { echo /var/lib/docker; exit 0; }
exit 99
EOF
chmod +x "$work/bin/"*

run() { # run <channel> -> output (stdout+stderr), status in $rc
    : > "$work/calls"
    out=$(HOME="$work/home" CALLS="$work/calls" RELEASE_LIST_RETRY_DELAY_S=0 GIT_NETWORK_MAX_ATTEMPTS=1 GIT_NETWORK_RETRY_DELAY_S=0 PATH="$work/bin:$PATH" \
        bash "$ROOT/install.sh" --channel "$1" --non-interactive </dev/null 2>&1)
    rc=$?
}
calls() { grep -c "^$1\$" "$work/calls"; }

run prerelease
if grep -Fxq 'Latest pre-release: v2026.11.1-rc.14' <<<"$out"; then pass "prerelease: the release list names the newest candidate"; else nope "prerelease: the release list names the newest candidate"; printf '%s\n' "$out" | head -8; fi

RELEASES_API=fail run prerelease
if grep -Fxq "GitHub's release list did not answer; using the releases feed instead." <<<"$out" \
    && grep -Fxq 'Latest pre-release: v2026.11.1-rc.14' <<<"$out" && [ "$(calls list)" = 4 ]; then
    pass "prerelease: after 4 unanswered tries the releases feed names the newest candidate"
else
    nope "prerelease: after 4 unanswered tries the releases feed names the newest candidate (list calls $(calls list))"; printf '%s\n' "$out" | head -8
fi

RELEASES_API=fail RELEASES_FEED=fail run prerelease
if [ "$rc" -ne 0 ] && grep -Fxq 'Error: Could not reach GitHub to find the newest StatBus release candidate. Run the same command again when GitHub answers.' <<<"$out" \
    && ! grep -q 'No pre-release published' <<<"$out"; then
    pass "prerelease: an unreachable GitHub is named, not reported as no pre-release"
else
    nope "prerelease: an unreachable GitHub is named, not reported as no pre-release (exit $rc)"; printf '%s\n' "$out" | head -8
fi

run stable
if grep -Fxq 'Latest stable release: v2026.11.0' <<<"$out"; then pass "stable: /releases/latest names the stable release"; else nope "stable: /releases/latest names the stable release"; printf '%s\n' "$out" | head -8; fi

LATEST_API=fail run stable
if grep -Fxq "GitHub's release list did not answer; using the releases page instead." <<<"$out" \
    && grep -Fxq 'Latest stable release: v2026.11.0' <<<"$out" && [ "$(calls latest)" = 4 ]; then
    pass "stable: after 4 unanswered tries the releases page names the stable release"
else
    nope "stable: after 4 unanswered tries the releases page names the stable release (latest calls $(calls latest))"; printf '%s\n' "$out" | head -8
fi

LATEST_API=fail RELEASES_FEED=fail run stable
if [ "$rc" -ne 0 ] && grep -Fxq 'Error: Could not reach GitHub to find the latest StatBus release. Run the same command again when GitHub answers.' <<<"$out" \
    && ! grep -q 'No stable release published' <<<"$out"; then
    pass "stable: an unreachable GitHub is named, not reported as no stable release"
else
    nope "stable: an unreachable GitHub is named, not reported as no stable release (exit $rc)"; printf '%s\n' "$out" | head -8
fi

if [ "$fail" = 0 ]; then echo "install release lookup test: PASS"; else echo "install release lookup test: FAIL"; exit 1; fi
