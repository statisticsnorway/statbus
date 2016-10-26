
Param(
  [string]$filePath
)
Get-ChildItem -Path $filePath\ -Filter project.json -Recurse | ForEach-Object { & dotnet restore $_.FullName 2>1 }