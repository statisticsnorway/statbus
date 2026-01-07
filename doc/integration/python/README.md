# Python Integration with StatBus REST API

This guide shows you how to integrate with the StatBus REST API using Python.

## Prerequisites

- Python 3.7 or higher
- Bash shell (available on Linux, macOS, WSL2, or Git for Windows)
- StatBus API credentials

## Quick Start

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```
   
   This will:
   - Check if Python is installed
   - Create a Python virtual environment (`.venv`)
   - Install required packages (requests, pandas, seaborn, matplotlib, python-dotenv)
   - Create a `.env` template file
   - Prompt you to edit the `.env` file with your credentials
   - Test the API connection

2. **Edit the `.env` file:**
   
   Open `.env` in a text editor and replace the placeholder values:
   ```bash
   API_URL=https://your-statbus-url
   API_KEY=your-api-key-here
   ```

3. **Activate the virtual environment:**
   ```bash
   source .venv/bin/activate
   ```

4. **Run the example:**
   ```bash
   python example.py
   ```

## What the Example Does

The `example.py` script:
- Loads configuration from the `.env` file
- Connects to the StatBus REST API
- Fetches statistical history data (establishment counts by year)
- Creates a bar chart visualization showing the trend over time
- Displays the chart in a window

## Manual Setup

If you prefer to set up manually:

```bash
# Create virtual environment
python3 -m venv .venv

# Activate it
source .venv/bin/activate

# Install packages
pip install requests pandas seaborn matplotlib python-dotenv
```

## Required Packages

- **requests**: HTTP library for API calls
- **pandas**: Data manipulation and analysis
- **seaborn**: Statistical data visualization
- **matplotlib**: Plotting library
- **python-dotenv**: Load environment variables from .env file

## API Usage Example

Here's a simple example of calling the StatBus API:

```python
import os
import requests
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

url = f"{os.getenv('API_URL')}/rest/statistical_history"
params = {
    "select": "year,countable_count",
    "unit_type": "eq.establishment",
    "resolution": "eq.year"
}
headers = {"Authorization": f"Bearer {os.getenv('API_KEY')}"}

response = requests.get(url, params=params, headers=headers)
response.raise_for_status()
data = response.json()
```

## Troubleshooting

### Import Error: No module named 'dotenv'
Make sure you've activated the virtual environment:
```bash
source .venv/bin/activate
```

### API Connection Error
- Verify your `.env` file has the correct URL and API key
- Check that your API key is still valid
- Ensure you have network access to the StatBus instance

### Python Not Found
Install Python 3.7 or higher from [python.org](https://www.python.org/downloads/)

## Next Steps

- Explore other API endpoints in your StatBus instance at `/rest/`
- Modify `example.py` to fetch different data sets
- Create custom visualizations based on your needs
