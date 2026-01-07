# R Integration with StatBus REST API

This guide shows you how to integrate with the StatBus REST API using R.

## Prerequisites

- R 4.0 or higher (download from [r-project.org](https://www.r-project.org/))
- Bash shell (available on Linux, macOS, WSL2, or Git for Windows)
- StatBus API credentials

## Quick Start

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```
   
   This will:
   - Check if R is installed
   - Create a `.env` file template
   - Prompt you to edit the `.env` file with your credentials
   - Install required R packages (httr2, ggplot2, dotenv)
   - Test the API connection

2. **Edit the `.env` file:**
   
   Open `.env` in a text editor and replace the placeholder values:
   ```bash
   API_URL=https://your-statbus-url
   API_KEY=your-api-key-here
   ```

3. **Run the example:**
   ```bash
   Rscript example.r
   ```
   
   Or open `example.r` in RStudio and run it interactively.

## What the Example Does

The `example.r` script:
- Loads configuration from the `.env` file using the `dotenv` package
- Connects to the StatBus REST API
- Fetches statistical history data (establishment counts by year)
- Creates a bar chart visualization showing the trend over time
- Displays the chart (saves to `establishments_by_year.png` in non-interactive mode)

## Manual Setup

If you prefer to set up manually in R:

```r
# Install packages (one-time setup)
install.packages("httr2")
install.packages("ggplot2")
install.packages("dotenv")
```

## Required Packages

- **httr2**: Modern HTTP client for API calls
- **ggplot2**: Data visualization (part of tidyverse)
- **dotenv**: Load environment variables from .env file

## API Usage Example

Here's a simple example of calling the StatBus API:

```r
library(httr2)
library(dotenv)

# Load environment variables
load_dot_env()

api_url <- Sys.getenv("API_URL")
api_key <- Sys.getenv("API_KEY")

# Make API request
url <- paste0(api_url, "/rest/statistical_history")
response <- request(url) |>
  req_url_query(
    select = "year,countable_count",
    unit_type = "eq.establishment",
    resolution = "eq.year"
  ) |>
  req_headers(Authorization = paste("Bearer", api_key)) |>
  req_perform()

# Parse response
data <- resp_body_json(response)
```

## Using with RStudio

1. Open RStudio
2. Set working directory to this folder: `Session > Set Working Directory > Choose Directory`
3. Open `example.r`
4. Make sure `.env` is configured with your credentials
5. Run the script line by line or all at once

## Troubleshooting

### Package Not Found
If you get an error about missing packages, install them manually:
```r
install.packages(c("httr2", "ggplot2", "dotenv"))
```

### Error: 'load_dot_env' not found
Make sure the `dotenv` package is installed:
```r
install.packages("dotenv")
```

### API Connection Error
- Verify your `.env` file has the correct URL and API key
- Check that your API key is still valid
- Ensure you have network access to the StatBus instance
- Try running the test in `setup.sh` again

### R Not Found
Install R from [r-project.org](https://www.r-project.org/) or [RStudio](https://posit.co/download/rstudio-desktop/)

### Chart Doesn't Display
If running non-interactively (with `Rscript`), the chart is saved to `establishments_by_year.png` in the current directory. Open this file to view the chart.

In RStudio, charts should display in the Plots pane.

## Next Steps

- Explore other API endpoints in your StatBus instance at `/rest/`
- Modify `example.r` to fetch different data sets
- Create custom analyses and visualizations based on your needs
- Use RStudio for interactive data exploration
