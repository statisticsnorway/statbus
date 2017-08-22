Param(
  # iis web app pool name
  [String]$poolname,
  # iis command: stop | whatever
  [String]$command
)

Import-Module WebAdministration

if ($command -eq "stop") {
  Write-Warning "stopping web app pool..."
  Stop-WebAppPool $poolname
} else {
  Write-Warning "starting web app pool..."
  Start-WebAppPool $poolname
}
