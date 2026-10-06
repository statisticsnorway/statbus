#!/usr/bin/env bash
# Default fleet cell: real cloud install handler, shared proof body.
set -euo pipefail
export CANDIDATE_PATH=operator
exec "$(dirname "$0")/5-install-source-image-identity-proof.sh" "${1:-statbus-recovery-5-install-source-identity-operator}"
