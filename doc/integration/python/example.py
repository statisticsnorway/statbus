#!/usr/bin/env python3
"""
StatBus REST API Example - Establishment Statistics Visualization

This script demonstrates how to:
1. Load credentials from .env file
2. Connect to the StatBus REST API
3. Fetch statistical history data
4. Visualize the data with a bar chart
"""

import os
import sys
import requests
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Get configuration
API_URL = os.getenv('API_URL')
API_KEY = os.getenv('API_KEY')

if not API_URL or not API_KEY:
    print("Error: API_URL and API_KEY must be set in .env file")
    print("Run ./setup.sh to create the .env file")
    sys.exit(1)

# API endpoint and parameters
url = f"{API_URL}/rest/statistical_history"
params = {
    "select": "year,countable_count",
    "unit_type": "eq.establishment",
    "resolution": "eq.year"
}
headers = {"Authorization": f"Bearer {API_KEY}"}

print("Fetching data from StatBus API...")
print(f"URL: {url}")
print("")

try:
    # Fetch the data
    response = requests.get(url, params=params, headers=headers, timeout=30)
    response.raise_for_status()  # Raises error if something went wrong
    
    # Parse JSON response
    data = response.json()
    
    if not data:
        print("Warning: No data returned from API")
        sys.exit(1)
    
    print(f"✓ Fetched {len(data)} records")
    
    # Convert to pandas DataFrame
    df = pd.DataFrame(data)
    
    # Ensure correct types
    df['year'] = df['year'].astype(int)
    df['countable_count'] = df['countable_count'].astype(int)
    
    # Sort by year
    df = df.sort_values('year')
    
    print(f"Years: {df['year'].min()} - {df['year'].max()}")
    print("")
    print("Data summary:")
    print(df.to_string(index=False))
    print("")
    
    # Create visualization
    print("Creating visualization...")
    plt.figure(figsize=(12, 7))
    sns.set_style("whitegrid")
    
    # Create bar plot
    ax = sns.barplot(
        data=df, 
        x='year', 
        y='countable_count', 
        hue='year', 
        palette='viridis',
        legend=False
    )
    
    # Add value labels on top of bars
    for container in ax.containers:
        ax.bar_label(container, fontsize=11, padding=3)
    
    # Customize plot
    plt.title("Number of Establishments per Year", fontsize=18, pad=20, fontweight='bold')
    plt.xlabel("Year", fontsize=14)
    plt.ylabel("Number of Establishments", fontsize=14)
    plt.xticks(rotation=45 if len(df) > 10 else 0)
    plt.tight_layout()
    
    print("✓ Visualization created")
    print("")
    print("Displaying chart (close the window to exit)...")
    plt.show()
    
    print("Done!")

except requests.exceptions.Timeout:
    print("Error: Request timed out. Check your network connection.")
    sys.exit(1)
except requests.exceptions.ConnectionError:
    print(f"Error: Could not connect to {API_URL}")
    print("Check that the URL is correct and the server is running.")
    sys.exit(1)
except requests.exceptions.HTTPError as e:
    print(f"Error: HTTP {response.status_code}")
    print(f"Response: {response.text[:500]}")
    sys.exit(1)
except Exception as e:
    print(f"Error: {str(e)}")
    sys.exit(1)
