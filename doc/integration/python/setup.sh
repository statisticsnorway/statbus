#!/bin/bash
set -e

echo "=========================================="
echo "StatBus Python Integration Setup"
echo "=========================================="
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed."
    echo "Please install Python 3.7 or higher from https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "✓ Found Python $PYTHON_VERSION"
echo ""

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file template..."
    cat > .env << 'EOF'
API_URL=
API_KEY=
EOF
    echo "✓ Created .env file"
    echo ""
    echo "⚠️  IMPORTANT: You must edit the .env file with your credentials!"
    echo ""
    echo "To get your API key:"
    echo "  1. Log into StatBus in your browser"
    echo "  2. Visit: https://your-statbus-url/rest/api_key?select=token"
    echo "  3. Copy the token value"
    echo ""
    echo "Then edit .env and set:"
    echo "  - API_URL to your StatBus instance URL (e.g., https://dev.statbus.org)"
    echo "  - API_KEY to your copied token"
    echo ""
    read -p "Press Enter after you've edited the .env file..."
    echo ""
else
    echo "✓ Found existing .env file"
    echo ""
fi

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Validate .env file - check URL first
if [ -z "$API_URL" ]; then
    echo "Error: API_URL not set in .env file"
    echo "Please edit .env and set your StatBus instance URL (e.g., https://dev.statbus.org)"
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY not set in .env file"
    echo "Please edit .env and set your API key"
    exit 1
fi

# Ensure API_URL ends with / for consistent URL construction
if [[ ! "$API_URL" =~ /$ ]]; then
    API_URL="${API_URL}/"
    export API_URL
    # Update .env file to persist the trailing slash
    sed -i.bak "s|^API_URL=.*|API_URL=$API_URL|" .env && rm .env.bak
fi

# Create virtual environment if it doesn't exist
if [ ! -d .venv ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv .venv
    echo "✓ Created virtual environment (.venv)"
    echo ""
else
    echo "✓ Found existing virtual environment (.venv)"
    echo ""
fi

# Activate virtual environment
echo "Activating virtual environment..."
source .venv/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip --quiet

# Install required packages
echo "Installing required packages..."
pip install requests pandas seaborn matplotlib python-dotenv --quiet
echo "✓ Installed: requests, pandas, seaborn, matplotlib, python-dotenv"
echo ""

# Test API connection
echo "Testing API connection..."
echo "URL: ${API_URL}rest/activity_category_standard"
echo ""

TEST_RESULT=$(python3 << PYTHON_SCRIPT
import os
import sys
import requests

# Get environment variables from shell (already loaded)
api_url = os.getenv('API_URL', '$API_URL')
api_key = os.getenv('API_KEY', '$API_KEY')

try:
    # Test with activity_category_standard endpoint (always has data)
    url = f"{api_url}rest/activity_category_standard"
    params = {"select": "name", "limit": "1"}
    headers = {"Authorization": f"Bearer {api_key}"}
    
    response = requests.get(url, params=params, headers=headers, timeout=10)
    
    if response.status_code == 200:
        print("SUCCESS")
        print(f"Status: {response.status_code}")
        data = response.json()
        if data:
            print(f"Sample response: {data[0]}")
        else:
            print("Warning: Empty response (no data in table)")
    elif response.status_code == 401:
        print("FAILED")
        print(f"Status: 401 Unauthorized")
        print("Your API_KEY is invalid or expired.")
        print("Please check your API key and update .env file.")
        sys.exit(1)
    elif response.status_code == 404:
        print("FAILED")
        print(f"Status: 404 Not Found")
        print(f"The API endpoint was not found at: {url}")
        print("Please check that your API_URL is correct (e.g., https://dev.statbus.org/)")
        sys.exit(1)
    else:
        print("FAILED")
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text[:200]}")
        sys.exit(1)
        
except requests.exceptions.ConnectionError as e:
    print("FAILED")
    print(f"Connection Error: Could not connect to {api_url}")
    print("Please check that:")
    print("  - The API_URL is correct")
    print("  - The server is running and accessible")
    print("  - You have network connectivity")
    sys.exit(1)
except requests.exceptions.Timeout:
    print("FAILED")
    print(f"Timeout: Request to {api_url} timed out after 10 seconds")
    print("The server may be slow or unreachable.")
    sys.exit(1)
except requests.exceptions.RequestException as e:
    print("FAILED")
    print(f"Error: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT
)

if echo "$TEST_RESULT" | grep -q "SUCCESS"; then
    echo "$TEST_RESULT"
    echo ""
    echo "=========================================="
    echo "✓ Setup completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Activate the virtual environment:"
    echo "     source .venv/bin/activate"
    echo ""
    echo "  2. Run the example script:"
    echo "     python example.py"
    echo ""
else
    echo "$TEST_RESULT"
    echo ""
    echo "=========================================="
    echo "✗ Setup completed but API test failed"
    echo "=========================================="
    echo ""
    echo "Please check:"
    echo "  - Your API_URL is correct in .env"
    echo "  - Your API_KEY is valid"
    echo "  - You have network access to the StatBus instance"
    echo ""
    exit 1
fi
