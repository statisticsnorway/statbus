#!/bin/bash
# Test script for importing Norway small history data through the REST API
# This test replicates the functionality in test/sql/50_import_jobs_for_norway_small_history.sql
# but uses the REST API instead of direct SQL connections.
#
# Usage: ./test/import_norway_small_history.sh [create|delete]
#   create: Set up and import Norway small history data (default)
#   delete: Clean up by removing imported data and definitions

set -euo pipefail

# Check for required parameter
if [ $# -lt 1 ]; then
  echo "Error: Missing required parameter (create or delete)"
  echo "Usage: $0 [create|delete]"
  echo "  create: Set up and import Norway small history data"
  echo "  delete: Clean up by removing imported data and definitions"
  exit 1
fi

# Validate parameter
ACTION="$1"
if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
  echo "Error: Invalid parameter. Must be 'create' or 'delete'"
  echo "Usage: $0 [create|delete]"
  exit 1
fi

# Enable debug mode if DEBUG is set
if test -n "${DEBUG:-}"; then
  set -x # Print all commands before running them - for easy debugging.
fi

# Determine workspace directory
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
pip install requests

# Verify installation was successful
if ! python -c "import requests" 2>/dev/null; then
  echo "Failed to install required packages. Please install manually:"
  echo "pip install requests"
  exit 1
fi

# Run the Python test script
echo "Running Norway small history import test (action: $ACTION)..."
python "$WORKSPACE/test/import_norway_small_history.py" "$ACTION"

# Deactivate virtual environment
deactivate
