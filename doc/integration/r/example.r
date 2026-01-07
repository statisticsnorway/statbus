#!/usr/bin/env Rscript
#
# StatBus REST API Example - Establishment Statistics Visualization
#
# This script demonstrates how to:
# 1. Load credentials from .env file
# 2. Connect to the StatBus REST API
# 3. Fetch statistical history data
# 4. Visualize the data with a bar chart
#

# Load required libraries
suppressPackageStartupMessages({
  library(ggplot2)
  library(httr2)
  library(dotenv)
})

cat("========================================\n")
cat("StatBus API Example - R\n")
cat("========================================\n\n")

# Load environment variables from .env file
tryCatch({
  load_dot_env()
}, error = function(e) {
  # If dotenv fails, try to read manually
  if (file.exists(".env")) {
    env_lines <- readLines(".env")
    env_lines <- env_lines[!grepl("^#", env_lines) & nchar(env_lines) > 0]
    for (line in env_lines) {
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      if (length(parts) == 2) {
        Sys.setenv(setNames(parts[2], parts[1]))
      }
    }
  }
})

# Get configuration
api_url <- Sys.getenv("API_URL")
api_key <- Sys.getenv("API_KEY")

if (api_url == "" || api_key == "") {
  cat("Error: API_URL and API_KEY must be set in .env file\n")
  cat("Run ./setup.sh to create the .env file\n")
  quit(status = 1)
}

# API endpoint
url <- paste0(api_url, "/rest/statistical_history")

cat("Fetching data from StatBus API...\n")
cat("URL:", url, "\n\n")

# Fetch the data
tryCatch({
  response <- request(url) |>
    req_url_query(
      select = "year,countable_count",
      unit_type = "eq.establishment",
      resolution = "eq.year"
    ) |>
    req_headers(Authorization = paste("Bearer", api_key)) |>
    req_perform()
  
  # Parse JSON response
  content <- resp_body_json(response)
  
  if (length(content) == 0) {
    cat("Warning: No data returned from API\n")
    quit(status = 1)
  }
  
  cat(paste("✓ Fetched", length(content), "records\n"))
  
  # Convert to data frame
  df <- as.data.frame(do.call(rbind, content))
  df$year <- as.integer(df$year)
  df$countable_count <- as.integer(df$countable_count)
  
  # Sort by year
  df <- df[order(df$year), ]
  
  cat(paste("Years:", min(df$year), "-", max(df$year), "\n\n"))
  cat("Data summary:\n")
  print(df, row.names = FALSE)
  cat("\n")
  
  # Create visualization
  cat("Creating visualization...\n")
  
  p <- ggplot(df, aes(x = factor(year), y = countable_count)) +
    geom_col(fill = "#2c7fb8", width = 0.7) +
    geom_text(
      aes(label = format(countable_count, big.mark = ",")), 
      vjust = -0.5, 
      size = 4,
      fontface = "bold"
    ) +
    labs(
      title = "Number of Establishments per Year",
      x = "Year",
      y = "Number of Establishments"
    ) +
    scale_y_continuous(
      labels = function(x) format(x, big.mark = ","),
      expand = expansion(mult = c(0, 0.15))
    ) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 16, margin = margin(b = 20)),
      axis.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = if(nrow(df) > 10) 45 else 0, hjust = if(nrow(df) > 10) 1 else 0.5),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )
  
  # Check if running interactively or in RStudio
  if (interactive() || Sys.getenv("RSTUDIO") == "1") {
    cat("✓ Visualization created\n")
    cat("\nDisplaying chart...\n")
    print(p)
    cat("\nChart displayed in the Plots pane\n")
  } else {
    # Save to file when running non-interactively (e.g., via Rscript)
    output_file <- "establishments_by_year.png"
    ggsave(
      output_file, 
      plot = p, 
      width = 10, 
      height = 6, 
      dpi = 300,
      bg = "white"
    )
    cat(paste("✓ Visualization saved to", output_file, "\n"))
  }
  
  cat("\nDone!\n")
  
}, error = function(e) {
  cat(paste("Error:", e$message, "\n"))
  
  if (grepl("Could not resolve host", e$message, ignore.case = TRUE)) {
    cat(paste("\nCould not connect to:", api_url, "\n"))
    cat("Check that the URL is correct and the server is running.\n")
  } else if (grepl("401", e$message)) {
    cat("\nAuthentication failed. Check that your API_KEY is correct.\n")
  } else if (grepl("403", e$message)) {
    cat("\nAccess forbidden. Check your API permissions.\n")
  } else if (grepl("404", e$message)) {
    cat("\nEndpoint not found. Check that the API URL is correct.\n")
  }
  
  quit(status = 1)
})
