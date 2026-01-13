# STATBUS

STATBUS [STATistical BUSiness Registry](https://www.statbus.org/) is a registry for tracking business activity throughout history in a country.
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

* Adaptation of the original data models with insights from SSB, and partner countries in asia and africa

## Technology Stack

* Backend with
  * [PostgreSQL](https://www.postgresql.org) (Database)
    * With [Row Level Security](https://www.postgresql.org/docs/18/ddl-rowsecurity.html)
    * With [SQL Saga](https://github.com/veridit/sql_saga) for Temporal Foreign Keys.
  * [PostgREST](https://postgrest.org/) (Automatic API from Database)
  * [Caddy](https://caddyserver.com) (Secure Web Server)
  * Our own custom auth (JWT authentication integrated with PostgREST)
    * One user one role - leveraging Row Level Security for secure API and database access.
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

#### Temporary & Scratch Directories

The project uses two temporary directories, `tmp/` and `app/tmp/`, as scratch pads, particularly for interaction with AI development tools.

-   These directories are tracked by Git (via a `.gitkeep` file) so they are present for all developers.
-   However, a `pre-commit` hook **prevents any files within them from ever being committed**.
-   This allows you to use them freely for local experiments and see AI-generated changes with `git diff`, without cluttering the project's history.

#### Git Hooks Setup (One-Time)

This project uses Git hooks to enforce conventions, like preventing commits from temporary directories. To enable these shared hooks, run the following command once after cloning the repository:

```bash
git config core.hooksPath devops/githooks
```

You only need to do this once. After setting the `hooksPath`, Git will automatically use the hooks located in `devops/githooks`, including any future updates to them. This ensures your commits are always checked against the latest project conventions.


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

Setup the database:

```bash
# First time setup only
./devops/manage-statbus.sh create-db-structure
./devops/manage-statbus.sh create-users

# Apply any pending database migrations
./cli/bin/statbus migrate up
```

### Database Migrations

The system uses a versioned migration system to manage database schema changes:

- Migrations are stored in `migrations/` directory.
- Each migration has an `up` and a `down` SQL file.
- Migration files are automatically named with a timestamp and tracked in the database.

Migration commands are run using the `statbus` command-line tool:
```bash
# Create a new migration file
./cli/bin/statbus migrate new --description "your description"

# Apply all pending migrations
./cli/bin/statbus migrate up

# Roll back the last applied migration
./cli/bin/statbus migrate down

# Roll back and re-apply the last migration
./cli/bin/statbus migrate redo
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

### Connecting to PostgreSQL Database

Statbus uses Caddy as a TLS-enabled Layer4 proxy for secure PostgreSQL connections. The proxy terminates TLS and routes connections based on Server Name Indication (SNI).

#### Local Development

For local development, the database is accessible through Caddy on a custom port (default: 3024):

```bash
# Use the provided helper script (recommended)
./devops/manage-statbus.sh psql

# Or connect manually with environment variables
eval $(./devops/manage-statbus.sh postgres-variables)
psql

# Or set environment variables manually
export PGHOST=local.statbus.org
export PGPORT=3024
export PGDATABASE=statbus_speed
export PGUSER=postgres
export PGPASSWORD=your_password
export PGSSLNEGOTIATION=direct
export PGSSLMODE=require
export PGSSLSNI=1
psql
```

**Environment Variables for Local Development**:

The `manage-statbus.sh postgres-variables` command exports these variables:

```bash
export PGHOST=local.statbus.org     # Domain (resolves to 127.0.0.1)
export PGPORT=3024                  # Caddy DB port (configurable via CADDY_DB_PORT)
export PGDATABASE=statbus_speed     # Database name (from POSTGRES_APP_DB)
export PGUSER=postgres              # Admin user (from POSTGRES_ADMIN_USER)
export PGPASSWORD=<generated>       # Admin password (from POSTGRES_ADMIN_PASSWORD)

# PostgreSQL 17+ TLS/SNI configuration
export PGSSLNEGOTIATION=direct      # Use modern direct TLS
export PGSSLMODE=require            # Require SSL but don't verify certificate
export PGSSLSNI=1                   # Send PGHOST as SNI (critical for Caddy routing)
```

The local environment uses:
- **Domain**: `local.statbus.org` (resolves to 127.0.0.1)
- **Port**: 3024 (configurable via `CADDY_DB_PORT`)
- **TLS**: Caddy's internal CA (self-signed)
- **SSL Mode**: `require` (encrypted but no certificate verification)

#### Production Deployment - Connecting to StatBus

If you're connecting to a deployed StatBus instance as a **user** (not for development), use environment variables to securely connect:

**Quick Connection** (secure one-liner with environment variables):

```bash
# Replace with your actual credentials and domain
PGHOST=your-statbus-domain.com PGPORT=5432 PGDATABASE=statbus PGUSER=your_username PGPASSWORD=your_password PGSSLNEGOTIATION=direct PGSSLMODE=verify-full PGSSLSNI=1 psql
```

**Example**:
```bash
PGHOST=statbus.example.com PGPORT=5432 PGDATABASE=statbus PGUSER=john PGPASSWORD=mysecretpass PGSSLNEGOTIATION=direct PGSSLMODE=verify-full PGSSLSNI=1 psql
```

**Or set environment variables first** (recommended for repeated connections):

```bash
# Set your connection parameters
export PGHOST=your-statbus-domain.com   # Your StatBus domain
export PGPORT=5432                      # Standard PostgreSQL port
export PGDATABASE=statbus               # Database name (usually 'statbus')
export PGUSER=your_username             # Your StatBus username
export PGPASSWORD=your_password         # Your password

# TLS/SNI configuration (PostgreSQL 17+ required)
export PGSSLNEGOTIATION=direct          # Use modern direct TLS (not STARTTLS)
export PGSSLMODE=verify-full            # Full certificate verification
export PGSSLSNI=1                       # Send hostname as SNI for routing

# Connect
psql
```

**For interactive password prompt** (most secure - doesn't store password):
```bash
# Set all parameters except password
export PGHOST=your-statbus-domain.com
export PGPORT=5432
export PGDATABASE=statbus
export PGUSER=your_username
export PGSSLNEGOTIATION=direct
export PGSSLMODE=verify-full
export PGSSLSNI=1

# Connect - will prompt for password
psql
```

**SSL Mode Options** (ordered by security level):
- `disable` - No SSL/TLS (not recommended)
- `allow` - Try SSL, fall back to unencrypted
- `prefer` - Prefer SSL, fall back to unencrypted
- `require` - Require SSL/TLS but don't verify certificate (development only)
- `verify-ca` - Require SSL and verify CA signature
- `verify-full` - Require SSL and verify hostname matches certificate (recommended for production)

**Important Notes**:
- **PostgreSQL 17+** is required for `PGSSLNEGOTIATION=direct` and `PGSSLSNI=1`
- The `PGSSLSNI=1` parameter is **critical** for Caddy's SNI-based routing in multi-tenant deployments
- Always use `verify-full` for production deployments with valid certificates
- Connection string format: `postgresql://user:password@domain:port/database?sslmode=verify-full&sslnegotiation=direct`

#### Connection Examples

**For end users connecting to StatBus with psql**:
```bash
# One-liner with environment variables (secure - credentials not visible in ps)
PGHOST=statbus.example.com PGPORT=5432 PGDATABASE=statbus PGUSER=yourname PGPASSWORD=yourpass PGSSLNEGOTIATION=direct PGSSLMODE=verify-full PGSSLSNI=1 psql

# Interactive password prompt (most secure)
PGHOST=statbus.example.com PGPORT=5432 PGDATABASE=statbus PGUSER=yourname PGSSLNEGOTIATION=direct PGSSLMODE=verify-full PGSSLSNI=1 psql
```

**Using connection URI** (for database tools and applications):
```bash
# Production - user connection (for tools that support URI format)
postgresql://yourname:yourpass@statbus.example.com:5432/statbus?sslmode=verify-full&sslnegotiation=direct

# Development - admin connection
postgresql://postgres:password@local.statbus.org:3024/statbus_speed?sslmode=require&sslnegotiation=direct
```

**Note**: Connection URIs are acceptable for application configuration files and tools, but for command-line psql, always use environment variables to avoid exposing credentials in process listings.

**Programming language examples**:

*Python (psycopg2/psycopg3)*:
```python
import psycopg2

conn = psycopg2.connect(
    host="statbus.example.com",
    port=5432,
    dbname="statbus",
    user="admin",
    password="password",
    sslmode="verify-full",
    sslnegotiation="direct"
)
```

*Node.js (pg)*:
```javascript
const { Client } = require('pg');

const client = new Client({
  host: 'statbus.example.com',
  port: 5432,
  database: 'statbus',
  user: 'admin',
  password: 'password',
  ssl: {
    rejectUnauthorized: true,  // verify-full
    sslnegotiation: 'direct'
  }
});

await client.connect();
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

### Backend (Services)
Start the Docker Containers with all services except the app

```bash
./devops/manage-statbus.sh start not_app
```


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


### Database Migrations

The system uses a versioned migration system to manage database schema changes:

- Migrations are stored in `migrations/` directory.
- Each migration has an `up` and a `down` SQL file.
- Migration files are automatically named with a timestamp and tracked in the database.

Migration commands are run using the `statbus` command-line tool:
```bash
# Create a new migration file
./cli/bin/statbus migrate new --description "your description"

# Apply all pending migrations
./cli/bin/statbus migrate up

# Roll back the last applied migration
./cli/bin/statbus migrate down

# Roll back and re-apply the last migration
./cli/bin/statbus migrate redo
```

### Loading Data into Statbus

Statbus comes with sample data files for Norway using NACE activity categories. Use the command palette (Ctrl+Shift+K) to access data loading options.

Loading sequence:

1. Select NACE as your activity standard
2. Upload Regions (download sample CSV from "What is Region file?")
3. Upload Sectors (download sample CSV)
4. Upload Legal Forms (download sample CSV) 
5. Upload Custom Activity Categories - Contains Norwegian translations for activity codes
6. Upload Legal Units - Sample uses Norwegian regions and NACE codes
7. Upload Establishments - Sample uses Norwegian regions and NACE codes
8. Refresh materialized views using command palette (Ctrl+Shift+K)

After loading data, the Dashboard will be visible on the front page. You can reset all data through the command palette.

### Data Loading Tips

- Start with classifications before loading units
- Test with a small sample of units first
- Verify classifications match your unit data
- See detailed guides at: https://www.statbus.org/files/Statbus_faq_load.html

### Cloud Testing Environment

Before local installation, we recommend testing Statbus in the cloud:

- Countries get dedicated domains for testing
- Test with country-specific classifications
- Start with limited test data
- Validate data model fits your needs
- Move to local installation once tested
