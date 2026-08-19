#!/bin/bash
# Exit immediately if any command exits with a non-zero status
set -e
# Print all commands if VERBOSE is defined
if [ -n "${VERBOSE}" ]; then
    set -x
fi

# STATBUS-250 — when a release candidate wrecks an automatic canary (dev)
# beyond what the recovery machinery (rollback/park/un-park) repairs, this
# is the one programmatic answer: wipe the slot, reinstall it at the
# previous STABLE release, and mark the wrecking candidate dismissed so the
# next discovery tick does not walk straight back into the poison.
#
# NOT a mode of create-new-statbus-installation.sh: that script verifies
# DNS, creates a Linux user, configures SSH access, and picks a port
# offset — none of which a reset needs, and all of which would be
# dangerous to re-run against a LIVE slot. This script reuses the
# TARGET_CHANNEL derivation PATTERN (STATBUS-251) and nothing else.
#
# NOT routed through the upgrade ledger (register/schedule): a reset is a
# DOWNGRADE by definition, and supersedeBelowInstalled (service.go:4491)
# retires any available/scheduled row whose newest tag is not newer than
# the installed version on the very next discovery tick — the scheduled
# reset row would be raced out from under itself. This is a DIRECT script
# path: stop the service, stop the stack, checkout, install, dismiss,
# restart.
#
# Usage: ./ops/reset-statbus-slot.sh <deployment_code> <wrecking-version> [reset-target]
# Example: ./ops/reset-statbus-slot.sh dev v2026.08.0-rc.12
# Example (explicit target): ./ops/reset-statbus-slot.sh dev v2026.08.0-rc.12 v2026.05.5
#
# The first two arguments are REQUIRED and there is no default — this wipes
# a database, so it must be impossible to run by accident on the wrong box,
# and the script must not guess which candidate wrecked the slot; only the
# human who diagnosed the wreck knows that. The third argument is OPTIONAL:
# an explicit reset target, overriding the auto-derivation below. It exists
# for the one case auto-derivation cannot resolve on its own — see the
# same-target refusal further down.
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <deployment_code> <wrecking-version> [reset-target]"
    echo "Example: $0 dev v2026.08.0-rc.12"
    echo "Example (explicit target): $0 dev v2026.08.0-rc.12 v2026.05.5"
    echo ""
    echo "The first two arguments are required. There is no default slot (this"
    echo "wipes a database) and no default wrecking version (the script must not"
    echo "guess which candidate to dismiss). The third argument is optional: an"
    echo "explicit reset target, for when the auto-derived one is not usable."
    exit 1
fi

DEPLOYMENT_SLOT_CODE="$1"
WRECKING_VERSION="$2"
RESET_TARGET_OVERRIDE="${3:-}"
DEPLOYMENT_USER="statbus_${DEPLOYMENT_SLOT_CODE}"
HOST="niue.statbus.org"

echo "══════════════════════════════════════════════════════════════════"
echo "  StatBus slot reset — STATBUS-250"
echo "  Slot:             $DEPLOYMENT_SLOT_CODE ($DEPLOYMENT_USER@$HOST)"
echo "  Wrecking version: $WRECKING_VERSION (will be dismissed, never re-offered)"
echo "══════════════════════════════════════════════════════════════════"

# RESET_TARGET (STATBUS-251's TARGET_CHANNEL derivation pattern, copied
# rather than reinvented — same git-tags source of truth, same regex).
# Difference from 251: 251 only needed to know WHICH CHANNEL a fresh
# install starts on; a reset needs the actual TAG to check out, so this
# resolves the newest matching tag itself, not just its existence.
#
# Previous STABLE, resolved GLOBALLY (King ruled 2026-08-19: reinstalling
# the previous release recreates the exact state a customer has, and dev's
# next auto-upgrade then walks the exact stable→next path a customer will
# take — crossing a release-line boundary if that is genuinely where the
# newest stable sits is the point: an office today has v2026.05.5, not an
# RC from a newer line). This is the newest `v*` tag ANYWHERE without an
# `-rc.` suffix — not scoped to "this line"; the code has never been scoped
# that way, an earlier draft of this comment said otherwise and was wrong
# about its own mechanism. RC FALLBACK fires only when NO stable tag exists
# AT ALL — currently UNREACHABLE (v2026.05.5 exists today) and therefore
# UNTESTED in practice; do not assume a green run has ever exercised it.
if [ -n "$RESET_TARGET_OVERRIDE" ]; then
    RESET_TARGET="$RESET_TARGET_OVERRIDE"
    echo "Reset target (explicit, third argument): $RESET_TARGET"
else
    git fetch --tags --quiet
    RESET_TARGET=$(git tag -l 'v*' --sort=-version:refname | grep -v -- '-rc\.' | head -1)
    if [ -z "$RESET_TARGET" ]; then
        RESET_TARGET=$(git tag -l 'v*' --sort=-version:refname | head -1)
        echo "NOTE: no stable release exists anywhere in this repo's tag history, so the"
        echo "      reset falls back to the newest tag of any kind — which may itself be"
        echo "      an RC, possibly the exact one that wrecked the box. Pass an explicit"
        echo "      reset target as the third argument if so."
    fi
    echo "Reset target: ${RESET_TARGET:-<none found>}"
fi

if [ -z "$RESET_TARGET" ]; then
    echo "Error: no tags found at all (v* stable or v*-rc.* prerelease) — cannot determine a reset target. Refusing." >&2
    exit 1
fi

if [ "$RESET_TARGET" = "$WRECKING_VERSION" ]; then
    echo "Error: the reset target ($RESET_TARGET) is the SAME as the wrecking version ($WRECKING_VERSION) — refusing to reinstall the box at the exact release being dismissed. Pass an explicit reset target as the third argument: $0 $DEPLOYMENT_SLOT_CODE $WRECKING_VERSION <reset-target>" >&2
    exit 1
fi

echo ""
echo "This will STOP the upgrade service, STOP all containers, check out"
echo "$RESET_TARGET, run ./sb install (recreating the database), and dismiss"
echo "$WRECKING_VERSION so it is never auto-installed again."
echo ""

echo "Resetting $DEPLOYMENT_USER@$HOST to $RESET_TARGET..."
ssh "$DEPLOYMENT_USER@$HOST" bash <<RESET_SLOT
    # Print commands if VERBOSE is defined
    if [ -n "${VERBOSE}" ]; then
        set -x
    fi
    set -e
    cd ~/statbus

    # Step 3: stop the upgrade service FIRST — otherwise the daemon can
    # discover, offer, or act mid-reset while we are tearing the box down
    # underneath it.
    echo "── stopping the upgrade service ──"
    systemctl --user stop "statbus-upgrade@\$USER.service"

    # Step 4: stop the stack.
    echo "── stopping services (./sb stop all) ──"
    ./sb stop all

    # Step 5: check out the reset target.
    echo "── checking out $RESET_TARGET ──"
    git fetch --tags --quiet
    git checkout "$RESET_TARGET"

    # Step 6: recreate the database and bring the box up at that version —
    # the same step-table path an operator has for everything else.
    echo "── running ./sb install ──"
    ./sb install

    # Step 7: dismiss the wrecking candidate. THE PRODUCT PATH, never a
    # direct row write (STATBUS-242's rewind hazard was cleared for this
    # exact case — a reset's writes sit OUTSIDE any upgrade window, so they
    # are inside the snapshot of every later upgrade and survive its
    # rollback — but only because this goes through the same code path
    # every other disposition does; a raw SQL write would not carry that
    # guarantee).
    echo "── dismissing $WRECKING_VERSION ──"
    ./sb upgrade dismiss "$WRECKING_VERSION"

    # Step 8: restart the service and verify from the RUNNING service, not
    # the file on disk — the same lesson as the fleet correction.
    echo "── restarting the upgrade service ──"
    systemctl --user restart "statbus-upgrade@\$USER.service"

    echo "── verifying: running channel ──"
    journalctl --user -u "statbus-upgrade@\$USER.service" --no-pager | grep "channel=" | tail -1

    echo "── verifying: $WRECKING_VERSION is dismissed and not offered ──"
    ./sb upgrade list
RESET_SLOT

echo ""
echo "Reset complete: $DEPLOYMENT_USER@$HOST is at $RESET_TARGET, $WRECKING_VERSION dismissed."
echo "Confirm above that the channel line and ./sb upgrade list both look correct —"
echo "this script does not itself judge the output; the operator does."
