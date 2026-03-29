#!/bin/sh
# Runtime injection of NEXT_PUBLIC_* environment variables.
#
# Next.js inlines NEXT_PUBLIC_* values at build time. To make pre-built
# images work across deployments (dev.statbus.org, no.statbus.org, etc.),
# the Dockerfile builds with __NEXT_PUBLIC_VARNAME__ placeholders.
# This script replaces them with actual runtime values before starting.
#
# Fail-fast: exits with error if any NEXT_PUBLIC_* var is empty or
# if any placeholder remains unreplaced after substitution.

set -e

PLACEHOLDER_PREFIX="__NEXT_PUBLIC_"
PLACEHOLDER_SUFFIX="__"
BUNDLE_DIR="/app/.next"
replaced=0
errors=""

# Replace each NEXT_PUBLIC_* env var's placeholder in the JS bundle
for var in $(env | grep '^NEXT_PUBLIC_' | cut -d= -f1); do
    value=$(eval echo "\$$var")
    placeholder="${PLACEHOLDER_PREFIX}${var#NEXT_PUBLIC_}${PLACEHOLDER_SUFFIX}"

    if [ -z "$value" ] || [ "$value" = "$placeholder" ]; then
        errors="${errors}  $var is not set (placeholder: $placeholder)\n"
        continue
    fi

    # Replace in all JS files — both .next/ (server-side) and public/_next/static/ (client-side).
    # Next.js copies static chunks to public/_next/static/ at build time, so both locations
    # contain placeholders that need runtime substitution.
    find "$BUNDLE_DIR" /app/public/_next/static -name '*.js' -exec sed -i "s|${placeholder}|${value}|g" {} + 2>/dev/null || true
    replaced=$((replaced + 1))
done

# Fail-fast: check for unreplaced placeholders in both locations
remaining=$(grep -rl "${PLACEHOLDER_PREFIX}" "$BUNDLE_DIR/static/" /app/public/_next/static/ 2>/dev/null | head -1 || true)
if [ -n "$remaining" ]; then
    echo "FATAL: Unreplaced NEXT_PUBLIC_* placeholders found in JS bundle:" >&2
    grep -roh "${PLACEHOLDER_PREFIX}[A-Z_]*${PLACEHOLDER_SUFFIX}" "$BUNDLE_DIR/static/" /app/public/_next/static/ 2>/dev/null | sort -u >&2
    echo "" >&2
    echo "Set these environment variables in docker-compose.app.yml" >&2
    exit 1
fi

if [ -n "$errors" ]; then
    echo "FATAL: Missing required NEXT_PUBLIC_* environment variables:" >&2
    printf "$errors" >&2
    exit 1
fi

if [ "$replaced" -gt 0 ]; then
    echo "Injected $replaced NEXT_PUBLIC_* runtime variable(s)"
fi

# Execute the original command (node server.js)
exec "$@"
