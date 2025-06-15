#!/bin/bash
# Test script for authentication in standalone mode
# Tests both API access and direct database access with the same credentials

set -euo pipefail

# Enable debug mode if DEBUG is set to true
if [ "${DEBUG:-}" = "true" ]; then
  set -x # Print all commands before running them - for easy debugging.
fi

# Determine workspace directory (similar to manage-statbus.sh)
WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd $WORKSPACE

# Set up Python virtual environment
VENV_DIR="$WORKSPACE/.venv"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$VENV_DIR"
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Install required packages
echo "Installing required Python packages..."
pip install requests psycopg2-binary

# Verify installation was successful
if ! python -c "import requests, psycopg2" 2>/dev/null; then
  echo "Failed to install required packages. Please install manually:"
  echo "pip install requests psycopg2-binary"
  exit 1
fi

# Run the Python test script
echo "Running authentication tests..."
python "$WORKSPACE/test/auth_for_standalone.py" "$@"

# Deactivate virtual environment
deactivate
