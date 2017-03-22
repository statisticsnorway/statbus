# Deployment

* more generalized instructions and error handling info is available in official documentation at [ASP.NET Core docs.microsoft.com](https://docs.microsoft.com/en-us/aspnet/core/publishing/iis)
* launching any executables, or even sign in, as _Administrator account_ is recommended during environment configuration

## prerequisites

* Windows 7 SP1 (or newer) or Windows Server 2008 R2 (or newer)

* [.NET 4.5.1](https://www.microsoft.com/en-us/download/details.aspx?id=40773) (or newer) installed

* Internet Information Services (IIS) Windows feature enabled

  1. Navigate to _Control Panel_ > _Programs_ > _Programs and Features_ > _Turn Windows features on or off_.
  1. Open the group for _Internet Information Services_ and _Web Management Tools_.
  1. Check the box for _IIS Management Console_.
  1. Check the box for _World Wide Web Services_.
  1. Accept the default features for _World Wide Web Services_.

* [PostgreSQL 9.6](https://www.enterprisedb.com/downloads/postgres-postgresql-downloads#windows) (or newer) installed

* [dotnet windows hosting](https://aka.ms/dotnetcore_windowshosting_1_1_0) installed (reboot after installation is recommended) bundle

## manual website configuration via IIS Manager

### add new or update existing website

1. On the target machine, create a folder to contain application's published folders and files.
1. Open the _IIS Manager_.
1. Click _Add Website_ from the _Sites_ contextual menu.
1. Supply the _Site name_, _Physical path_ to the application's deployment folder that you created.
1. In the _Application Pools_ panel, open the _Edit Application Pool_ window by right-clicking on the website's application pool and selecting _Basic Settings..._ from the popup menu.
1. Select _Basic Settings_ from the contextual menu of the _Application Pool_.
1. Set the _.NET CLR version_ to _No Managed Code_.

### ensure that newly configured AppPool is being used by our website

### ensure that created AppPool has appropriate permissions (read and write) on the Website host directory

1. Open _Windows Explorer_ and navigate to the directory.
1. Right click on the directory and click _Properties_.
1. Under the _Security_ tab, click the _Edit_ button and then the _Add_ button.
1. Click the _Locations_ button and make sure your server is selected.
1. Enter configured application pool identity (default is **IIS AppPool\DefaultAppPool**) in _Enter the object names_ to select textbox.
1. Select users or groups dialog for the application folder.
1. Click the _Check Names_ button and then click _OK_.
1. Select users or groups dialog for the application folder.

## database setup

1. Open _pgAdmin_ application.
1. Configure binary path: select _Servers_ tree node in menu on left side and click _Configure pgAdmin_ link in main window.
1. Set _Paths_ > _Binary paths_ > _PostgreSQL Binary Path_ value to PostgreSQL's binaries installation directory (default value is **C:\Program Files\PostgreSQL\9.6\bin**) and click _OK_ button.
1. Expand _Servers_ tree node on leftside menu.
1. Click in context menu on installed server (default server name is **PostgreSQL 9.6**) > _Create_ > _Database_.
1. Set database name and click _Save_ button.
1. Update _DefaultConnection_ value in ```appsettings.Production.json``` file to use the database.

PS: in development phase the shape of data (database structure) would change frequently and database delivery mechanism is not figured out yet.
Few possible solutions are next:

* before running web application database update via migrations should be performed (development environment is required):
  1. update _DefaultConnection_ value in ```appsettings.json``` of _nscreg.Data_ project to point to target database;
  1. open command prompt and execute **dotnet ef database update** command;
* with breaking changes (in case of database structure) developers should provide backup of up-to-date database (to be discussed, leads to data loss).

## website continuous deployment

* Install Web Deploy 3.6
* Configure firewall to allow inbound rules:
  1. if ip address only access: HTTPS required, port 5986
  1. if fully qualified domain name (FQDN) access: HTTP and port 5985 or HTTPS and port 5986
* If HTTPS is required - supply (or create self signed, for test or development purposes) certificate:
  1. Windows 8.1/Windows Server 2012 and later can use `NewSelfSignedCertificate` cmdlet via PowerShell (more details to be described)
  1. Earlier OS versions can use `makecert.exe` utility (more details to be described)
* In case of HTTP error code 500.19 try running this PowerShell script:
  ```PowerShell
  Import-Module WebAdministration
  Set-WebConfiguration `
    -Filter "/System.webServer/modules" `
    -Metadata overrideMode `
    -Value Allow `
    -PSPath "IIS:\"
  ```
* Database access to run seed scripts? (more details to be described)

## Troubleshooting

* *%IIS website root folder%\logs* - application log files directory
* *Event Viewer > Windows Logs > Application* - IIS and AppPool logs
