# prerequisites

* more generalized instructions is available in official documentation at [ASP.NET Core docs.microsoft.com](https://docs.microsoft.com/en-us/aspnet/core/publishing/iis)
* launching any executables, or sign in as Administrator is preferred during environment configuration

- Windows 7 SP1 (or newer) with [.NET 4.5.1](https://www.microsoft.com/en-us/download/details.aspx?id=40773) (or newer) installed
- installed PostgreSQL 9.6 (or newer)
- enabled Internet Information Services Windows feature (default checkbox state on toggling is enough)
- installed [dotnet windows hosting](https://aka.ms/dotnetcore_windowshosting_1_1_0) (reboot after installation is recommended) bundle

## manual website configuration on IIS

- add new or update existing website to host on specified folder on disk (e.g. C:\nscreg)
- set application pool's .NET CLR version value to "No Managed Code" (in Basic Settings)
