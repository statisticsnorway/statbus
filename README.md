# STATBUS

**[STATistical BUSiness Registry](https://www.statbus.org/)**

STATBUS is a registry for tracking business activity throughout history in a country.
It offers a unique database approach, using temporal tables so that one can view a timeline
of the information. This allows after the fact querying at any point in time.

STATBUS is developed by [Statistics Norway(SSB)](https://www.ssb.no/).

## Goals

Our motto is *Simple to Use, Simple to Understand, Simply Useful*

In 2023 we changed the technology stack with the following goals in mind:

* Make it easy to get started with statbus in a local installation.
  Have a wizard/guide to help set up required configuration.

* Make it easy and fast to enter data and get feedback.
  Either by simple web creation, or by fast batch processing.

* Make it easy to create custom reports with a simple graph,
  support excel/csv export for custom graphing/processing.
  The report system can used for a specific year, month and day,
  to see development over time.

* Simple and secure advanced database integration for custom setups and integration.

* Adaptation of the original data models with the newest insights from SSB,
  as well as a host of database cleanups accumulated over the years.

## Technology Stack

* [Supabase](https://supabase.com) with
  * [PostgreSQL](https://www.postgresql.org) (Database)
    * With [Row Level Security](https://www.postgresql.org/docs/16/ddl-rowsecurity.html)
  * [PostgREST](https://postgrest.org/) (Automatic API from Database)
  * GoTrue (Supabase JWT authentication integrated with PostgREST)
* [Next.js](https://nextjs.org) (app with backend and frontend)
  * Using the [TypeScript Language](https://www.typescriptlang.org).
  * [Shadcn](https://ui.shadcn.com) Library for components with UI and behaviour.
  * [TailwindCSS](https://tailwindcss.com) For styling.
  * [Highcharts](https://www.highcharts.com) For graphing.
* [Docker](https://www.docker.com) for managing application images
  * [Docker Compose](https://docs.docker.com/compose/) for orchestration for local development and production deployment.


## Running Locally

### Requirements

* [Docker](https://www.docker.com) Container Managment.
* [Git](https://www.git-scm.com) Source Code Control.
* Unix Shell - comes with macOS and any Linux, for windows use *Git Bash*.

### Instructions

Clone the repository to your local machine using Git:

```bash
git clone https://github.com/statisticsnorway/statbus.git
cd statbus
```

Create initial users by copying `.users.example` to `.users.yml` and adding your admin access users.

Generate Configuration Files

```bash
./devops/manage-statbus.sh generate-config
```

This command will create the .env, .env.credentials, and .env.config files with the required environment variables.

Start the Docker Containers with all services.

```bash
./devops/manage-statbus.sh start
```

Setup the database / Seed (Only first run)
```bash
./devops/manage-statbus.sh activate_sql_saga
./devops/manage-statbus.sh create-db-structure
./devops/manage-statbus.sh create-users
```

Connect to your local statbus at http://localhost:3000 with
the users you specified in `.users.yml`.

The Supabase admin panel is available at http://localhost:3001
See the file `.env.credentials` for generated secure login credentials.

From that point on you can manage with
```bash
./devops/manage-statbus.sh stop
```

and

```bash
./devops/manage-statbus.sh start
```

### Teardown

To remove all data and start over again you can do
```bash
./devops/manage-statbus.sh stop
./devops/manage-statbus.sh delete-db

rm -f .env.credentials .env.config .env
```


## Local Development

### Requirements

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


<!--
  -- Uncommented non active workflows from the old development workflow.
[![CI](https://github.com/statisticsnorway/statbus/actions/workflows/ci-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/ci-workflow.yaml)
[![CD](https://github.com/statisticsnorway/statbus/actions/workflows/cd-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/cd-workflow.yaml)
[![Linter](https://github.com/statisticsnorway/statbus/actions/workflows/linter-workflow.yaml/badge.svg)](https://github.com/statisticsnorway/statbus/actions/workflows/linter-workflow.yaml)
-->


### Frontend

The project needs the Node version specified in the .nvmrc file, that is automatically
handled by nvm as mentioned in the requirements.

The app for int

Linux/Ubuntu and macOs:

```sh
cd app
nvm use
npm run start
```

Windows:

When running Git Bash
```sh
nvm install $(cat .nvmrc | tr -d '[:space:]')
nvm use $(cat .nvmrc | tr -d '[:space:]')
npm install
npm run start
```

Notice that "nvm" is a tool to install the correct node version,
with the corresponding npm version, and activate it.
Notice that Windows has an `nvm` that behaves differently.

<!--
## Use an external database

The Docker Compose files are configured with a bridged network, allowing the services to reach the outside. If you want to run statbus with an external database you need to change the references to sql19-latest to the IP address of the database you want to use.

## Versioning

Statbus uses the [GitVersion action](https://github.com/GitTools/actions) for semantic versioning. Major and minor versions can be bumped by commit messages and git tags

## GitHub Actions Workflows

The GitHub workflows can be run locally with [ACT](https://github.com/nektos/act). This is installed in the [devcontainer](#devcontainer). There are vscode tasks for running each of the workflows.
-->


### Loading Stabus with data
Statbus comes with sample datafiles for Norway running on NACE activity categories
At the bottom rigth corner there is a command palette, Ctrl+shift+K to jump to the different loads.

1) Select Nace as your standard
2) When Uploading Regions, click what is Region file, and download the csv sample file to upload
3) Sectors, What is a sector file, download and upload the csv file
4) Legal Forms, What is a Legal Forms file, download and upload the csv
5) Custom Activity Categories, What is, download and upload. This file contains the nowegian names on the already defined codes in english. This file makes Statbus pront the activity codes in norwegian instead of english
6) Legal Units. sample file contains norwegian region codes, and NACE standard. If you have selected ISIC in step 1, the sample file will cause confusion.
7) Establishments, sample file contain norwegian regions and NACE standard. This file should currently be the source for the statistical variables.
8) When loaded 1-7, use command palette to refresh the materialized view: Refresh Statistical Units, a short json status will be visible, then go to the frontpage, and the Dashboard should be visible. This functionality is hidden behind the Command Palette, Ctrl+shift+K. From here you can reset everything, which deletes! all your dataloads 1-7, and will guide you to the start again.

### Uploading tips
Make sure you get the classifications as good as possible before starting with units. A small unit file is recomended, in order to verify that classifications are matching the data loaded in the unit-loads (7 & 8)
Error messages, hints and teqniques are described at: www.statbus.org   https://www.statbus.org/files/Statbus_faq_load.html


