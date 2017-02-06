Param(
  # iis website name
  [String]$sitename,
  # iis website command: stop | whatever
  [String]$command
)

Import-Module WebAdministration

if ($command == "stop") {
  Write-Information "stopping website..."
  Stop-WebSite $sitename
} else {
  Write-Information "starting website..."
  Start-WebSite $sitename
}
