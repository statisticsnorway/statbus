Param(
  # iis web app pool name
  [String]$path,
  # iis command: stop | whatever
  [String]$command
)

if ($command -eq "stop") {
  Write-Warning "stopping datauploadsvc..."
  dotnet $path/nscreg.Server.DataUploadSvc.dll action:$command
} else {
  Write-Warning "starting datauploadsvc..."
  dotnet $path/nscreg.Server.DataUploadSvc.dll action:start
}
