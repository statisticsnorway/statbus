#!/bin/bash
# Test concurrent worker processing with isolated database
#
# Usage:
#   ./test/test_concurrent_worker.sh [-n THREADS] [-t TASKS]
#   ./test/test_concurrent_worker.sh --list           # List previous test DBs
#   ./test/test_concurrent_worker.sh --cleanup        # Delete DB after run
#
# Databases are RETAINED by default for comparison across runs.
# Each run creates test_concurrent_<PID> which you can inspect later.

set -euo pipefail

# Enable debug mode if DEBUG is set
if test -n "${DEBUG:-}"; then
  set -x
fi

# Determine workspace directory
WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd "$WORKSPACE"

# Build worker binary if needed (check both worker.cr and cli.cr)
BINARY="$WORKSPACE/cli/bin/statbus"
if [ ! -f "$BINARY" ] || [ "$WORKSPACE/cli/src/worker.cr" -nt "$BINARY" ] || [ "$WORKSPACE/cli/src/cli.cr" -nt "$BINARY" ]; then
  echo "Building worker binary..."
  cd "$WORKSPACE/cli" && shards build statbus
  cd "$WORKSPACE"
fi

# Set up Python virtual environment
VENV_DIR="$WORKSPACE/.venv"

if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

# Install required packages (skip if already installed)
python3 -c "import psycopg2" 2>/dev/null || pip install -q psycopg2-binary

# Run the test with unbuffered output for real-time monitoring
exec python3 -u "$WORKSPACE/test/test_concurrent_worker.py" "$@"
