Param(
  # CMD executable name
  [String]$source,
  # CMD parameters
  [String]$output
)

Write-Warning "unzipping $source to $output..."
& {
  Add-Type -A "System.IO.Compression.FileSystem"
  [IO.Compression.ZipFile]::ExtractToDirectory("$source", "$output", $true)
}
