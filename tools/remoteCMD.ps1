Param(
  # CMD executable name
  [String]$command,
  # CMD parameters
  [String]$params
)

if ($command -ne $null -and $command -ne '') {
  Write-Warning "executing script: $command"
  Write-Warning "with params: $params"
  & $command $params
}
