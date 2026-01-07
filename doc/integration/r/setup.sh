#!/bin/bash
set -e

echo "=========================================="
echo "StatBus R Integration Setup"
echo "=========================================="
echo ""

# Check if R is installed
if ! command -v R &> /dev/null && ! command -v Rscript &> /dev/null; then
    echo "Error: R is not installed."
    echo "Please install R from https://www.r-project.org/"
    echo "Or install RStudio Desktop from https://posit.co/download/rstudio-desktop/"
    exit 1
fi

R_VERSION=$(R --version | head -n1)
echo "✓ Found $R_VERSION"
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

# Install required R packages
echo "Installing required R packages..."
echo "This may take a few minutes on first run..."
echo ""

Rscript - << 'R_SCRIPT'
# Function to install package if not already installed
install_if_missing <- function(package) {
  if (!require(package, character.only = TRUE, quietly = TRUE)) {
    cat(paste("Installing", package, "...\n"))
    install.packages(package, repos = "https://cloud.r-project.org/", quiet = TRUE)
    if (require(package, character.only = TRUE, quietly = TRUE)) {
      cat(paste("✓ Installed", package, "\n"))
    } else {
      cat(paste("✗ Failed to install", package, "\n"))
      quit(status = 1)
    }
  } else {
    cat(paste("✓", package, "already installed\n"))
  }
}

# Install required packages
install_if_missing("httr2")
install_if_missing("ggplot2")
install_if_missing("dotenv")

cat("\n✓ All required packages are installed\n")
R_SCRIPT

if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Failed to install R packages"
    exit 1
fi

echo ""

# Test API connection
echo "Testing API connection..."
echo "URL: ${API_URL}rest/activity_category_standard"
echo ""

TEST_RESULT=$(API_URL="$API_URL" API_KEY="$API_KEY" Rscript - << 'R_SCRIPT'
suppressPackageStartupMessages({
  library(httr2)
})

# Get environment variables from shell (already loaded)
api_url <- Sys.getenv("API_URL")
api_key <- Sys.getenv("API_KEY")

# Test connection
tryCatch({
  # Test with activity_category_standard endpoint (always has data)
  url <- paste0(api_url, "rest/activity_category_standard")
  
  response <- request(url) |>
    req_url_query(
      select = "name",
      limit = "1"
    ) |>
    req_headers(Authorization = paste("Bearer", api_key)) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()
  
  status <- resp_status(response)
  
  if (status == 200) {
    cat("SUCCESS\n")
    cat(paste("Status:", status, "\n"))
    data <- resp_body_json(response)
    if (length(data) > 0) {
      cat(paste("Sample response:", names(data[[1]]), "=", unlist(data[[1]]), "\n"))
    } else {
      cat("Warning: Empty response (no data in table)\n")
    }
  } else if (status == 401) {
    cat("FAILED\n")
    cat("Status: 401 Unauthorized\n")
    cat("Your API_KEY is invalid or expired.\n")
    cat("Please check your API key and update .env file.\n")
    quit(status = 1)
  } else if (status == 404) {
    cat("FAILED\n")
    cat("Status: 404 Not Found\n")
    cat(paste("The API endpoint was not found at:", url, "\n"))
    cat("Please check that your API_URL is correct (e.g., https://dev.statbus.org/)\n")
    quit(status = 1)
  } else {
    cat("FAILED\n")
    cat(paste("Status:", status, "\n"))
    body <- tryCatch(resp_body_string(response), error = function(e) "Unable to read response")
    cat(paste("Response:", substr(body, 1, 200), "\n"))
    quit(status = 1)
  }
  
}, error = function(e) {
  cat("FAILED\n")
  error_msg <- e$message
  
  if (grepl("Could not resolve host", error_msg, ignore.case = TRUE)) {
    cat(paste("Connection Error: Could not connect to", api_url, "\n"))
    cat("Please check that:\n")
    cat("  - The API_URL is correct\n")
    cat("  - The server is running and accessible\n")
    cat("  - You have network connectivity\n")
  } else if (grepl("timed out", error_msg, ignore.case = TRUE)) {
    cat(paste("Timeout: Request to", api_url, "timed out\n"))
    cat("The server may be slow or unreachable.\n")
  } else {
    cat(paste("Error:", error_msg, "\n"))
  }
  
  quit(status = 1)
})
R_SCRIPT
)

if echo "$TEST_RESULT" | grep -q "SUCCESS"; then
    echo "$TEST_RESULT"
    echo ""
    echo "=========================================="
    echo "✓ Setup completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "  Run the example script:"
    echo "    Rscript example.r"
    echo ""
    echo "  Or open in RStudio:"
    echo "    Open example.r in RStudio and run interactively"
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
