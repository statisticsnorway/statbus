#!/bin/bash
# Test script for authentication against https://dev.statbus.org/
# Attempts to reproduce issues outlined in auth-problem.md

set -euo pipefail

# Enable debug mode if DEBUG is set to true
if [ "${DEBUG:-}" = "true" ]; then
  set -x # Print all commands before running them - for easy debugging.
fi

# Determine workspace directory
WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd "$WORKSPACE"

# Credentials will be fetched by the Python script.

# Set up Python virtual environment (same as auth_for_standalone.sh)
VENV_DIR="$WORKSPACE/.venv"

if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

echo "Installing required Python packages..."
pip install -r "$WORKSPACE/test/requirements-dev.txt" --quiet

if ! python -c "import requests, yaml" 2>/dev/null; then
  echo "Failed to install required packages. Please check test/requirements-dev.txt and ensure pip is working."
  exit 1
fi

# Run the Python test script for dev.statbus.org
echo "Running authentication tests against https://dev.statbus.org/..."
# Pass environment variables explicitly to the Python script if needed,
# or ensure the Python script reads them directly using os.environ.
# The current Python template will use os.environ.
python "$WORKSPACE/test/auth_for_dev.statbus.org.py"

# Deactivate virtual environment
deactivate
