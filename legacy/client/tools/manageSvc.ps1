Param(
  # iis web app pool name
  [String]$dllpath,
  # iis command: stop | whatever
  [String]$command
)

if ($command -eq "stop") {
  Write-Warning "stopping svc..."
  dotnet $dllPath action:uninstall
} else {
  Write-Warning "starting svc..."
  dotnet $dllPath action:install
}
