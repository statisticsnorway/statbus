Param(
  # CMD executable name
  [String]$source,
  # CMD parameters
  [String]$output
)

Write-Warning "unzipping $source to $output..."
Expand-Archive -Path $source -DestinationPath $output -Force
