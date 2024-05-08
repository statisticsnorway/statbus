# Statbus

Statistical Business Registry (SBR)

[![CI](https://github.com/statisticsnorway/statbus/actions/workflows/ci-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/ci-workflow.yaml)
[![CD](https://github.com/statisticsnorway/statbus/actions/workflows/cd-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/cd-workflow.yaml)
[![Linter](https://github.com/statisticsnorway/statbus/actions/workflows/linter-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/linter-workflow.yaml)


## Tools Stack

* .Net 7.0 with Asp.Net 7.x and Entity Framework Core 7.x,
* ElasticSearch 6.5.3
* React 16.8.4/Redux 3.7.2/React-Router 3.2.0, Semantic UI 0.86.0
* Node 8.11.4
* PostgreSQL (from docker)

## test servers / Credentials

## Devcontainer

The project specifies a devcontainer that can be used when workling locally. This has the advantage that you don't need to install tools such as dotnet, nodejs etc locally. More info can be found in the [vscode documentation](https://code.visualstudio.com/docs/devcontainers/containers)

## Running a development build

Requirements

* Windows
  * Git for Windows with *Git Bash* for running `sh` code blocks.
  * Scoop https://scoop.sh/
    For installing packages from the command line.
  * NVM-Windows https://github.com/coreybutler/nvm-windows
    Install with `scoop install nvm`
* Linux (Ubuntu/Debian)
  * Node Version Manager https://github.com/nvm-sh/nvm
    Install with `apt install nvm`
* macOS
  * Homebrew https://brew.sh/
    For installing packages from the command line.
  * Node Version Manager https://github.com/nvm-sh/nvm
    Install with `brew install nvm`
* .Net 7.x
* Docker


### Git Line Ending Handling

This project uses the LF line ending.
Git on windows will, depending on installation method, change from LF to CRLF,
that breaks the running of scripts both from command line and when building
with Docker (Compose).

Configure git on your system with:
```
git config --global core.autocrlf true
```

Ref. https://stackoverflow.com/a/13154031/1023558

If the project was checked out on Windows, with the incorrect line endings,
then to fix the issue, use visual studio code to open the files
* `dbseed\InsertPostgresData.sql`
* `docker-postgres\init-user-db.sh`

And change the line encoding in the lower right corner from "CRLF" to "LF"
before following the instructions below.

### Services

To run a local development build, the required services must be run with

```sh
docker compose -f docker-compose.support-services-postgres.yml up
```

To stop the services *(without deleting the database)*, press Ctrl + C.

*To delete the database*, and start fresh, run the command
```sh
docker compose -f docker-compose.support-services-postgres.yml down --volumes
```


### Migrations, Seed and Backend

Then the backend can be started with an IDE or with the following command

```sh
dotnet run --environment Development --project src/nscreg.Server
```

When the backend runs on an empty database, it will run all migrations
and create the required tables.

### Seed data (if first run)
If this is the first run of the docker services, the Server will run
a migration that creates all the tables in the project.
Then one must import the seed data required for Statbus to operate:

```sh
./devops/manage-statbus.sh psql < dbseed/InsertPostgresData.sql 2>&1
```
Notice the `2>&1` that ensures error messages are returned, in case
of problems.


### Frontend

The project needs the Node version specified in the .nvmrc file.

And the frontend is started with

Linux/Ubuntu and macOs:

```sh
nvm install
nvm use
npm install
npm run watch
```

Windows:

When running Git Bash
```sh
nvm install $(cat .nvmrc | tr -d '[:space:]')
nvm use $(cat .nvmrc | tr -d '[:space:]')
npm install
npm run watch
```

Notice that "nvm" is a tool to install the correct node version,
with the corresponding npm version, and activate it. Notice that Windows  

This will read the client files and continously update the files served by the dotnet
backend from src/nscreg.Server/wwwwroot
To load new frontend code the page must be reloaded, as hot reload is not possible
with this configuration.

### How to add new assets to the project

To add new assets to the project you need to edit the copy job defined in the run.mjs file under the tools folder and package.json.

Say for example that you want to add a new icons folder to the project, then you need to update run.mjs with the following:

```
tasks.set('clean', () =>
  Promise.resolve()
    .then(() =>
      del(
        [
          './build/*',
          './src/nscreg.Server/wwwroot/*',
          '!./build/.git',
        ],
        { dot: true },
      ))
    .then(() => mkdirp.sync('./src/nscreg.Server/wwwroot/fonts'))
	.then(() => mkdirp.sync('./src/nscreg.Server/wwwroot/icons')))
```

And:

```
{
   src: "./client/icons",
   dest: "./src/nscreg.Server/wwwroot/icons",
   isSync: true,
}
```

Finally, you need to update package.json with the following:

```
{
   "staticPath": "./client/icons",
   "distDir": "./src/nscreg.Server/wwwroot/icons"
}
```

That's it. Now run ```npm run build``` to compile and copy the files accordingly.

### Browser

Then Visit <http://localhost:5000/> u:admin p:123qwe

## Running a production build

### .env file

We use an `.env`-file for selecting the correct Docker Compose file. This is by default configured to:

```sh
COMPOSE_FILE=docker-compose.debug.yml
```

To run a production build, change it to:

```sh
COMPOSE_FILE=docker-compose.yml
```

and then do a compose up

```sh
docker-compose up -d
```

The `-d` parameter runs docker in the background. You can inspect docker log output with `docker compose logs`.

## Database language (TODO)

Language of the database is set in `docker-compose.yml` These must be set before initializing the server for the first time.

English

```yaml
environment:
    MSSQL_LCID: 1033
    MSSQL_COLLATION: SQL_Latin1_General_CP1_CI_AS
```

Russian

```yaml
environment:
    MSSQL_LCID: 1049
    MSSQL_COLLATION: Cyrillic_General_CI_AS
```

## Restore at database

If you want to use a local database in a docker container and restore the database from a backup file, follow the instructions below:

1) move the backup file to the directory `dbackups` in the root directory of the project

2) change the `name-of-db` within the following command and run the commands afterwards:

    ``` bash
    docker stop nscreg.server
    docker exec -it sql19-latest /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U SA -P '12qw!@QW' \
    -Q "RESTORE DATABASE [name-of-db] \
        FROM  DISK = N'/var/dbackups/name-of-db.bak' WITH FILE = 1, \
        MOVE N'name-of-db' TO N'/var/opt/mssql/data/name-of-db.mdf', \
        MOVE N'name-of-db_log' TO N'/var/opt/mssql/data/name-of-db_log.ldf',\
        NOUNLOAD,  REPLACE,  STATS = 5"
    docker start nscreg.server
    ```

    **Example with `SBR_NOR.bak` file**

    ``` bash
    docker stop nscreg.server
    ```

    ``` bash
    docker exec -it sql19-latest /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U SA -P '12qw!@QW' \
    -Q "RESTORE DATABASE [SBR_NOR] \
        FROM DISK = N'/var/dbackups/SBR_NOR.bak' WITH FILE = 1, \
        MOVE N'SBR_NOR'     TO N'/var/opt/mssql/data/SBR_NOR.mdf', \
        MOVE N'SBR_NOR_log' TO N'/var/opt/mssql/data/SBR_NOR.ldf',\
        NOUNLOAD, REPLACE, STATS = 5"
    ```

    ``` bash
    docker start nscreg.server
    ```

    **Example with `DEMO.bak` file**

    ``` bash
    docker stop nscreg.server
    ```

    ``` bash
    docker exec -it sql19-latest /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U SA -P '12qw!@QW' \
    -Q "RESTORE DATABASE [SBR_NOR] \
        FROM DISK = N'/var/dbackups/DEMO.bak' WITH FILE = 1, \
        MOVE N'DEMO'     TO N'/var/opt/mssql/data/SBR_NOR.mdf', \
        MOVE N'DEMO_log' TO N'/var/opt/mssql/data/SBR_NOR.ldf',\
        NOUNLOAD, REPLACE, STATS = 5"
    ```

    ``` bash
    docker start nscreg.server
    ```

3) you should be able to see the last string of the output as below:

    ``` bash
    RESTORE DATABASE successfully processed 938 pages in 0.157 seconds (46.651 MB/sec).
    ```

## Enable HTTPS/SSL

HTTPS/SSL can be enabled in statbus with the following changes to `docker-compose.debug.yml`

- `services.server.environment` - Add environment variables for certificate location and password
  ``` yaml
  - ASPNETCORE_Kestrel__Certificates__Default__Password=CERT_PASSWORD
  - ASPNETCORE_Kestrel__Certificates__Default__Path=/https/CERT_NAME
  ```
  Example with password `MySecurePassword` and certificate name `localhost.pfx`
  ``` yaml
  - ASPNETCORE_Kestrel__Certificates__Default__Password=MySecurePassword
  - ASPNETCORE_Kestrel__Certificates__Default__Path=/https/localhost.pfx
  ```
- `services.server.volumes` - Add volume mapping for certificate
  ``` yaml
  - LOCAL_CERTIFICATE_PATH:/https:ro
  ```
  Example with certificate stored in the `.aspnet/https` subfolder of the users home directory
  ``` yaml
  - ~/.aspnet/https:/https:ro
  ```

## Use an external database

The Docker Compose files are configured with a bridged network, allowing the services to reach the outside. If you want to run statbus with an external database you need to change the references to sql19-latest to the IP address of the database you want to use.

## Versioning

Statbus uses the [GitVersion action](https://github.com/GitTools/actions) for semantic versioning. Major and minor versions can be bumped by commit messages and git tags

## GitHub Actions Workflows

The GitHub workflows can be run locally with [ACT](https://github.com/nektos/act). This is installed in the [devcontainer](#devcontainer). There are vscode tasks for running each of the workflows.

## Notes

To clean everything docker related run ```docker system prune --all --volumes```

To remove all files not under version control ```git clean -fdx```

* <https://nodejs.org/en/about/releases/>
* <https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core>

```sh
node -p "process.arch"
x64                     # 'arm64' wil not work yet
```

[mcr.microsoft.com/mssql/server](https://hub.docker.com/_/microsoft-mssql-server) does not support Apple M1 (ARM64)~~, some suggest to use [mcr.microsoft.com/azure-sql-edge](https://hub.docker.com/_/microsoft-azure-sql-edge)~~

[Docker Desktop 4.16](https://docs.docker.com/desktop/release-notes/#4160) and newer now supports Apple M1 (ARM64)

> New Beta feature for macOS 13, Rosetta for Linux, has been added
for faster emulation of Intel-based images on Apple Silicon.

# Statbus Remastered

**Simple to use, simply useful**

All complete rewrite that focuses on the main goals of the project.
* Make it easy to get started with statbus in a local installation.
  Have a wizard/guide to help set up required configuration.

* Make it easy and fast to enter data and get feedback.
  Either by simple web creation, or by fast batch processing.

* Make it easy to create custom reports with a simple graph,
  support excel/csv export for custom graphing/processing.
  The report system can used for a specific year, month and day,
  to see development over time.

* Simple and secure advanced database integration for custom setups.

* Adaptation of the original data models with the newest insights from SSB,
  as well as a host of database cleanups accumulated over the years.

## Technology Stack

* Supabase with
  * PostgreSQL (Database)
    * With Row Level Security
  * PostgREST (Automatic API from Database)
  * GoTrue (JWT authentication integrated with PostgREST)
* Sveltekit
* Fomantic UI https://fomantic-ui.com, a fork of Semantic UI.
* Node v18

## Supabase

This project use Supabase services as a docker compose setup.
This was set up as a git submodule.

Management of supabase is done with `./devops/manage-supabase.sh`.

## Sveltekit

Start development with `npm run dev -- --open`.

