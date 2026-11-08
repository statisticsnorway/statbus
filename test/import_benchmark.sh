#!/bin/bash
# Benchmark the BRREG import through the real worker, in an isolated database
#
# Usage:
#   ./test/import_benchmark.sh [--dataset selection|downloads|mixed] [-t TIMEOUT]
#   ./test/import_benchmark.sh --dataset selection [--valid-from YYYY-MM-DD | --year YYYY]
#   ./test/import_benchmark.sh --result-json tmp/benchmark.json [--require-import-concurrency MIN]
#   ./test/import_benchmark.sh --list           # List previous benchmark DBs
#   ./test/import_benchmark.sh --cleanup        # Delete DB after run
#
# Databases are RETAINED by default for comparison across runs.
# Each run creates import_benchmark_<PID> which you can inspect later.
# MIN is an acceptance assertion on durable processing-leaf intervals, not a
# queue configuration override. The serial default works without this option.

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
exec python3 -u "$WORKSPACE/test/import_benchmark.py" "$@"
