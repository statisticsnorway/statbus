#!/bin/bash
# Verify that a published image index is anonymously deployable and identical
# to the source index it was built or retagged from.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source-image-ref> <destination-image-ref>" >&2
    exit 2
fi

SOURCE_REF="$1"
DESTINATION_REF="$2"
MAX_ATTEMPTS="${PUBLIC_IMAGE_VERIFY_ATTEMPTS:-3}"
RETRY_DELAY_S="${PUBLIC_IMAGE_VERIFY_RETRY_DELAY_S:-10}"

anonymous_config=$(mktemp -d)
output_file=$(mktemp)
trap 'rm -rf "$anonymous_config" "$output_file"' EXIT

registry_failure_class() {
    local message="$1"
    if printf '%s\n' "$message" | grep -Eqi 'unauthorized|denied|authentication required|insufficient[_ -]?scope|(^|[^0-9])(401|403)([^0-9]|$)'; then
        printf '%s\n' auth
    elif printf '%s\n' "$message" | grep -Eqi 'manifest unknown|not found|no such manifest|(^|[^0-9])404([^0-9]|$)'; then
        printf '%s\n' missing
    elif printf '%s\n' "$message" | grep -Eqi 'timeout|timed out|connection reset|connection refused|temporary failure|tls handshake|context deadline|network is unreachable|unexpected eof|i/o timeout'; then
        printf '%s\n' network
    else
        printf '%s\n' unknown
    fi
}

inspect_digest() {
    local mode="$1" ref="$2" attempt rc output class digest
    INSPECT_DIGEST=""
    INSPECT_FAILURE_CLASS=unknown
    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        : > "$output_file"
        if [ "$mode" = anonymous ]; then
            if DOCKER_CONFIG="$anonymous_config" docker buildx imagetools inspect "$ref" >"$output_file" 2>&1; then
                rc=0
            else
                rc=$?
            fi
        elif docker buildx imagetools inspect "$ref" >"$output_file" 2>&1; then
            rc=0
        else
            rc=$?
        fi

        output=$(cat "$output_file")
        if [ "$rc" -eq 0 ]; then
            digest=$(printf '%s\n' "$output" | awk '$1 == "Digest:" { print $2; exit }')
            if [ -n "$digest" ]; then
                INSPECT_DIGEST="$digest"
                return 0
            fi
            echo "ERROR: ${mode} inspect of $ref returned no index digest:" >&2
            printf '%s\n' "$output" | sed 's/^/  /' >&2
            return 1
        fi

        class=$(registry_failure_class "$output")
        echo "Registry inspect retry [$mode][$class] ${attempt}/${MAX_ATTEMPTS} for $ref (rc=$rc)" >&2
        printf '%s\n' "$output" | sed 's/^/  /' >&2
        if [ "$class" = unknown ] || [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
            INSPECT_FAILURE_CLASS="$class"
            return 1
        fi
        sleep "$RETRY_DELAY_S"
    done
}

echo "Verifying published image: $SOURCE_REF -> $DESTINATION_REF"
if inspect_digest authenticated "$SOURCE_REF"; then
    source_digest="$INSPECT_DIGEST"
else
    echo "ERROR: source image cannot be inspected: $SOURCE_REF" >&2
    exit 1
fi

if inspect_digest anonymous "$DESTINATION_REF"; then
    destination_digest="$INSPECT_DIGEST"
else
    class="$INSPECT_FAILURE_CLASS"
    echo "ERROR: destination image is not anonymously deployable [$class]: $DESTINATION_REF" >&2
    if [ "$class" = auth ]; then
        package_name="${DESTINATION_REF%%:*}"
        package_name="${package_name##*/}"
        echo "REMEDY: GitHub Packages -> $package_name -> Package settings -> Change visibility -> Public, then rerun Images." >&2
    fi
    exit 1
fi

if [ "$source_digest" != "$destination_digest" ]; then
    echo "ERROR: image index digest mismatch:" >&2
    echo "  source      $SOURCE_REF = $source_digest" >&2
    echo "  destination $DESTINATION_REF = $destination_digest" >&2
    exit 1
fi

echo "Anonymous destination verified; index digest matches source: $destination_digest"
