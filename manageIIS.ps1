Param(
  # iis website name
  [String]$sitename,
  # iis website command: stop | whatever
  [String]$command
)

Import-Module WebAdministration

if ($command -eq "stop") {
  Write-Warning "stopping website..."
  Stop-WebSite $sitename
} else {
  Write-Warning "starting website..."
  Start-WebSite $sitename
}
