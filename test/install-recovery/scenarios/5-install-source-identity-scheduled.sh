#!/usr/bin/env bash
# Default fleet cell: real scheduled inline install, shared proof body.
set -euo pipefail
export CANDIDATE_PATH=scheduled
exec "$(dirname "$0")/5-install-source-image-identity-proof.sh" "${1:-statbus-recovery-5-install-source-identity-scheduled}"
