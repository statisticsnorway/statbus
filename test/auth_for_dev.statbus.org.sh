#!/bin/bash
# Test script for authentication against https://dev.statbus.org/
# Attempts to reproduce issues outlined in auth-problem.md

set -euo pipefail

# Enable debug mode if DEBUG is set
if test -n "${DEBUG:-}"; then
  set -x # Print all commands before running them - for easy debugging.
fi

# Determine workspace directory
WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd "$WORKSPACE"

# Check for required environment variables
if [ -z "${STATBUS_DEV_EMAIL:-}" ] || [ -z "${STATBUS_DEV_PASSWORD:-}" ]; then
  echo "Error: STATBUS_DEV_EMAIL and STATBUS_DEV_PASSWORD environment variables must be set."
  echo "Usage: STATBUS_DEV_EMAIL=\"your_email\" STATBUS_DEV_PASSWORD=\"your_password\" $0"
  exit 1
fi

# Set up Python virtual environment (same as auth_for_standalone.sh)
VENV_DIR="$WORKSPACE/.venv"

if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

echo "Installing required Python packages (requests)..."
pip install requests --quiet

if ! python -c "import requests" 2>/dev/null; then
  echo "Failed to install requests. Please install manually: pip install requests"
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
