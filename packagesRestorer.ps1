
Param(
  [string]$filePath
)
Get-ChildItem -Path $env:BUILD_REPOSITORY_LOCALPATH\$filePath\ -Filter project.json -Recurse | ForEach-Object { & dotnet restore $_.FullName 2>1 }