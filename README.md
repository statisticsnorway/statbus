# Statbus

Statistical Business Registry (SBR)

[![CI](https://github.com/statisticsnorway/statbus/actions/workflows/ci-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/ci-workflow.yaml)
[![CD](https://github.com/statisticsnorway/statbus/actions/workflows/cd-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/cd-workflow.yaml)
[![Linter](https://github.com/statisticsnorway/statbus/actions/workflows/linter-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/linter-workflow.yaml)


## tools stack

* .Net 7.0 with Asp.Net 7.x and Entity Framework Core 7.x,
* ElasticSearch 6.5.3
* React 16.8.4/Redux 3.7.2/React-Router 3.2.0, Semantic UI 0.86.0
* Node 8.11.4

## test servers / Credentials

## Devcontainer

The project specifies a devcontainer that can be used when workling locally. This has the advantage that you don't need to install tools such as dotnet, nodejs etc locally. More info can be found in the [vscode documentation](https://code.visualstudio.com/docs/devcontainers/containers)

## Running a development build

### Without Docker

Requirements

* Windows, Linux, macOS
* .Net 7.x
* Node.js 16

```sh
npm ci --legacy-peer-deps
npm run build
dotnet restore
dotnet build
dotnet test (TODO)
```

### With Docker Compose

Requirements

* Windows, Linux, macOS
* Docker, recent version with Compose support.

Docker compose is used to start the required servers, databsae and elasticsearch,
as well as to build and run the backend and frontend in a consistent environment.

There are two configuration files, one for running in development mode with debug
support and one for running with relase code.

To start with local development with debug support, i.e. possibility to attach to the
dotnet server, use

```sh
docker compose -f docker-compose.debug.yml up
```

To start with local development without debug support, i.e. frontend only development, use

```sh
docker compose -f docker-compose.yml up
```

Then Visit <http://localhost/> u:admin p:123qwe

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
