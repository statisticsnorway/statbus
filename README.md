# nscreg-norway

Statistical Business Registry (SBR)

[![CI](https://github.com/statisticsnorway/statbus/actions/workflows/ci.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/ci.yaml)

## tools stack

* ASP.NET Core 3.1, Entity Framework Core 3.1.22, ElasticSearch 6.5.3
* React.js 16.8.4/Redux 3.7.2/React-Router 3.2.0, Semantic UI 0.86.0
* Node 8.11.4
* Dotnet-Sdk-3.1.416

## test servers / Credentials

Staging (тестовая) 
http://192.168.1.23:817/
http://timelysoft.org:817/ - Внешка 

http://192.168.1.23:888 - SQL Wallet
http://timelysoft.org:888/  - SQL Wallet внешка

Авторизация на сайте:
admin
123qwe

Sql wallet авторизация:
admin
1234!Q2w

RDP
192.168.1.23
Administrator
1234!@QW

## Running a development build

Requirements
* Windows, Linux, Macos (Apple M1 is currently a problem)
* .NET Core 3.1 SDK
* Node.js 16
* Docker

```sh
npm ci --legacy-peer-deps
npm run build
dotnet restore
dotnet build
dotnet test (TODO)
```
or
```sh
docker-compose up -–build -d
```

Visit http://localhost/ u:admin p:123qwe
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

    ```
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

    ```
    docker stop nscreg.server
    ```
    ```
    docker exec -it sql19-latest /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U SA -P '12qw!@QW' \
    -Q "RESTORE DATABASE [SBR_NOR] \
        FROM DISK = N'/var/dbackups/SBR_NOR.bak' WITH FILE = 1, \
        MOVE N'SBR_NOR'     TO N'/var/opt/mssql/data/SBR_NOR.mdf', \
        MOVE N'SBR_NOR_log' TO N'/var/opt/mssql/data/SBR_NOR.ldf',\
        NOUNLOAD, REPLACE, STATS = 5"
    ```
    ```
    docker start nscreg.server
    ```

    **Example with `DEMO.bak` file**

    ```
    docker stop nscreg.server
    ```
    ```
    docker exec -it sql19-latest /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U SA -P '12qw!@QW' \
    -Q "RESTORE DATABASE [SBR_NOR] \
        FROM DISK = N'/var/dbackups/DEMO.bak' WITH FILE = 1, \
        MOVE N'DEMO'     TO N'/var/opt/mssql/data/SBR_NOR.mdf', \
        MOVE N'DEMO_log' TO N'/var/opt/mssql/data/SBR_NOR.ldf',\
        NOUNLOAD, REPLACE, STATS = 5"
    ```
    ```
    docker start nscreg.server
    ```
3) you should be able to see the last string of the output as below:

    ```
    RESTORE DATABASE successfully processed 938 pages in 0.157 seconds (46.651 MB/sec).
    ```


## Notes

To clean everything docker related run ```docker system prune --all --volumes```

To remove all files not under version control ```git clean -fdx``` 

* https://nodejs.org/en/about/releases/
* https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core

```sh
node -p "process.arch"
x64                     # 'arm64' wil not work yet
```



[mcr.microsoft.com/mssql/server](https://hub.docker.com/_/microsoft-mssql-server) does not support Apple M1 (ARM64), some suggest to use [mcr.microsoft.com/azure-sql-edge](https://hub.docker.com/_/microsoft-azure-sql-edge)
