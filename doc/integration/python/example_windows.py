# StatBus REST API example (Windows) - fetches statistical history for establishments.
#
# Prerequisites:
#   pip install requests python-dotenv
#
# Create a .env file in the same directory with:
#   API_URL=https://your-statbus-instance.org
#   API_KEY=your_api_key_here
#
# Run:
#   python example_windows.py

import json
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
print(response.text)
data = response.json()
print(json.dumps(data, indent=2))
