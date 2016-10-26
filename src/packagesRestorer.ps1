
Param(
  [string]$filePath
)
Get-ChildItem -Path $env:AGENT_HOMEDIRECTORY\$filePath\ -Filter project.json -Recurse | ForEach-Object { & dotnet restore $_.FullName 2>1 }