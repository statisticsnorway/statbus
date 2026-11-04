#!/usr/bin/env bash
# STATBUS-488: an operator prepares a box with the setup script of the release
# being installed, never from master. STATBUS-571: every operator document
# shows that as a piped command from a released source:
#   https://statbus.org/setup.sh        latest stable release's asset
#   https://statbus.org/rc/setup.sh     newest candidate's asset (ops/rc resolver)
#   https://github.com/statisticsnorway/statbus/releases/download/<tag>/setup-ubuntu-lts.sh
# This test reads every setup command in the operator documents and requires
# each to be one of those, piped to bash. It then checks the two shortcuts
# land on release assets: statbus.org/setup.sh is redirected by niue's Caddy
# to releases/latest/download (checked live when the network allows), and the
# /rc/ resolver downloads releases/download/<tag>/setup-ubuntu-lts.sh.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DOCS=(README.md doc/setup-ubuntu-lts.md doc/DEPLOYMENT.md doc/hetzner-bootstrap.md ops/setup-ubuntu-lts.sh ops/manual-box.sh)
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

released='(https://statbus\.org/(rc/)?setup\.sh|https://github\.com/statisticsnorway/statbus/releases/download/(v[0-9]{4}\.[0-9]{2}\.[0-9]+(-rc\.[0-9]+)?|<tag>)/setup-ubuntu-lts\.sh)'
for doc in "${DOCS[@]}"; do
    file="$ROOT/$doc"
    # Every command line that fetches the setup script.
    lines=$(grep -nE 'curl[^|]*(setup\.sh|setup-ubuntu-lts\.sh)' "$file" | grep -v 'statbus.org/rc/install\|install\.sh')
    if [ -z "$lines" ]; then
        nope "$doc shows no setup command"
        continue
    fi
    bad=$(grep -vE "curl -fsSL $released \| ([A-Z_]+=\"[^\"]*\" )?bash( -s -- .*)?\$" <<<"$lines" | sed -E 's/^([0-9]+):\s*#?\s*/\1: /')
    if [ -z "$bad" ]; then
        pass "$doc: every setup command is piped from a released source"
    else
        nope "$doc: setup command not piped from a released source:"
        printf '    %s\n' "$bad"
    fi
    if grep -nE 'statbus/(refs/heads/)?master/ops/setup-ubuntu-lts\.sh|-o (setup|harden)\.sh' "$file"; then
        nope "$doc still downloads the setup script to a file or from master"
    fi
done

# The /rc/ resolver fetches the candidate's own release asset.
if grep -q 'ASSET=setup-ubuntu-lts.sh' "$ROOT/ops/rc/setup.sh" \
    && grep -q 'releases/download/$tag/$ASSET' "$ROOT/ops/rc/setup.sh"; then
    pass "statbus.org/rc/setup.sh runs the candidate's release asset"
else
    nope "statbus.org/rc/setup.sh runs the candidate's release asset"
fi

# statbus.org/setup.sh is a redirect on niue; check it live when reachable.
if loc=$(curl -fsS -o /dev/null -w '%{redirect_url}' --max-time 10 https://statbus.org/setup.sh 2>/dev/null); then
    if [ "$loc" = https://github.com/statisticsnorway/statbus/releases/latest/download/setup-ubuntu-lts.sh ]; then
        pass "statbus.org/setup.sh redirects to the latest release's asset"
    else
        nope "statbus.org/setup.sh redirects to '$loc'"
    fi
else
    echo "SKIP statbus.org/setup.sh not reachable from here"
fi
exit $fail
