# Statbus Service Architecture

## Overview

Statbus is a containerized application built with PostgreSQL, PostgREST, and Next.js.
The architecture uses Docker Compose to orchestrate multiple services,
with Caddy serving as a reverse proxy and authentication gateway.

## Core Services

### Database (PostgreSQL)
- **Container**: `statbus-{slot}-db`
- **Purpose**: Stores all application data and handles authentication logic
- **Key Features**:
  - Custom PostgreSQL image with extensions (sql_saga, pgjwt, pg_graphql, etc.)
  - Row Level Security for integrated security.
    - Each use is a separate role (email) with an access role:
  - Role-based access control
    - admin_user - Can do everything
    - regular_user - Can enter data - but not change setup.
    - restricted_user - Can only insert and edit data for selected regions or activity_categories.
    - external_user - Can see everything - but not change anything.
  - JWT-based authentication system
    - Each user is a separate database role.
    - Each user has a designated statbus role.
  - Temporal data tracking using valid time with foreign keys.

### API Layer (PostgREST)
- **Container**: `statbus-{slot}-rest`
- **Purpose**: Provides RESTful API access to the database
- **Key Features**:
  - Automatic REST API generation from database schema
  - JWT validation and role switching
  - Aggregation support for analytics
  - Exposes pg_graphql.

### Web Server (Caddy)
- **Container**: `statbus-{slot}-caddy`
- **Purpose**: Reverse proxy and authentication gateway
- **Key Features**:
  - Routes `/postgrest/*` requests to PostgREST using POSTGREST_BIND_ADDRESS (via postgrest_endpoints)
    - Notice that the auth related functions are callable by anonymous, and to themselves
      process cookies, ensure security and return cookies. (login/refresh/logout/auth_status)
  - Routes all other requests to the Next.js app using APP_BIND_ADDRESS
  - Handles cookie-to-header JWT conversion
  - Manages authentication flow (login, logout, refresh)
  - Supports multiple deployment modes
    - development for running Application locally
    - private for running on a server behind a host caddy that handles https.
    - standalone for running on a server handling official domain and https.

### Application (Next.js)
- **Container**: `statbus-{slot}-app`
- **Purpose**: Server-side rendered web application
- **Key Features**:
  - TypeScript-based React application
  - Server-side rendering for performance
  - Communicates with PostgREST API via Caddy

### Background Worker
- **Container**: `statbus-{slot}-worker`
- **Purpose**: Handles background tasks and jobs
- **Key Features**:
  - Built with Crystal
  - Direct database access for efficiency
  - Runs data analysis.
  - Runs import jobs.

## Authentication Flow

1. **Login**: User credentials sent to `/postgrest/rpc/login`, validated by PostgreSQL function
   and returns cookies with JWT tokens.
2. **Token Management**: JWT tokens stored in cookies (`statbus-{slot}` and `statbus-{slot}-refresh`)
3. **API Access**: Caddy extracts JWT from cookies and adds as Authorization headers for `/postgrest/*` routes,
   since [PostgREST does not support reading the JWT access token from a cookie](https://github.com/PostgREST/postgrest/issues/3033)
4. **Token Refresh**: Automatic refresh via `/postgrest/rpc/refresh` endpoint that consumes the jwt refresh token,
   that can only be used once, and is found in the cookie, and returns a new access token and refresh token as cookies.
5. **Logout**: Reads tokens from cookies and clears them as well as removing the refresh token.

## Caddy Deployment Modes

The system supports three deployment modes for the Caddy service, controlled by the `CADDY_DEPLOYMENT_MODE` environment variable:

### 1. Development Mode
- **Purpose**: For local development with Next.js running separately
- **Features**:
  - API forwarding to PostgREST
  - Message for non-API requests (since Next.js runs locally)
  - HTTP only (no HTTPS)
- **Usage**: 
  ```bash
  # In .env.config
  CADDY_DEPLOYMENT_MODE=development
  ```
  ```bash
  ./devops/manage-statbus.sh start all_except_app
  ```

### 2. Private Mode
- **Purpose**: For deployment behind a public proxy
- **Features**:
  - Trusts headers from forwarding proxy
  - API forwarding to PostgREST
  - Other paths to Next.js app
  - HTTP only (HTTPS handled by public proxy)
- **Usage**: 
  ```bash
  # In .env.config
  CADDY_DEPLOYMENT_MODE=private
  ```

### 3. Standalone Mode
- **Purpose**: For direct public access
- **Features**:
  - Handles HTTPS directly with automatic certificate management
  - API forwarding to PostgREST
  - Other paths to Next.js app
  - Includes public-facing configuration
- **Usage**: 
  ```bash
  # In .env.config
  CADDY_DEPLOYMENT_MODE=standalone
  ```

## Environment Configuration

The application uses a layered approach to environment configuration:

1. **Base Configuration Files**:
   - `.env.credentials`: Contains stable credentials (passwords, secrets) - Generated once per deployment.
   - `.env.config`: Contains deployment-specific configuration - Generated and adjusted for deployment code and domain.
   - `.env`: Generated from the above files, by manage.cr, used by both Docker Compose and local development.
   - `caddy/config/development.caddyfile`: For local development - only HTTP
   - `caddy/config/private.caddyfile`: For deployment on server, running behind a host caddy using `public.caddyfile`
   - `caddy/config/public.caddyfile`: For inclusion in a host wide caddy installation serving multiple deployments.
   - `caddy/config/standalone.caddyfile`: For standalone deployment on server (same functionality as public+private combined in same server)

2. **Key Configuration Variables** (Edit in `.env.config`):
   - `DEPLOYMENT_SLOT_NAME`: Human-readable name
   - `DEPLOYMENT_SLOT_CODE`: Code used in URLs and container names
   - `CADDY_DEPLOYMENT_MODE`: Controls how Caddy operates (development, private, standalone)
   - `SITE_DOMAIN`: Domain for the publicly available site (required and used in standalone mode, as well as in the public.caddyfile)

3. **Docker Compose vs Local Development**:
   - When running in Docker: Environment variables are hard-coded in `docker-compose.app.yml`
   - When running locally: Environment variables are read from the project `.env` file.

### Docker Compose Profiles

The system uses Docker Compose profiles to control which services start:

- `all`: All services (database, API, app, worker)
- `all_except_app`: All backend services without the Next.js app (for local development)

### Local Development Setup

For local Next.js development:

1. **Start Backend Services in Development Mode**:
   ```bash
   ./devops/manage-statbus.sh start all_except_app
   ```

2. **Run Next.js Locally**:
   ```bash
   cd app
   pnpm run dev
   ```

3. **Development Environment**:
   - In `.env.config` set `CADDY_DEPLOYMENT_MODE=development` and generate `.env`
   - The local Next.js app runs on http://localhost:3000
   - Caddy serves as an API gateway on NEXT_PUBLIC_BROWSER_API_URL
   - All API requests from the local Next.js app go through Caddy
   - Caddy handles authentication by converting cookies to JWT headers
     - Caddy includes the `development.caddyfile` where
       CORS headers are automatically configured for local development

### Environment Variable Flow

1. **For Docker Deployment**:
   ```
   .env.credentials + .env.config -(generate-config)→ .env → docker-compose.*.yml → container environment
   ```

2. **For Local Development**:
   ```
   .env.credentials + .env.config -(generate-config)→ .env → next.config.js → Next.js environment
   ```

This approach ensures consistent configuration between Docker and local development environments
while allowing for the flexibility of running the Next.js app locally for faster development cycles.

## Deployment Configuration

The system supports multiple deployment slots for different countries (ma(rocco),no(rway),jo(rdan),...) through environment variables:

- `DEPLOYMENT_SLOT_NAME`: Human-readable name
- `DEPLOYMENT_SLOT_CODE`: Code used in URLs and container names
- `NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE`: Exposed to browser.
- `NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME`: Exposed to browser.
- `DEPLOYMENT_SLOT_PORT_OFFSET`: Used to generate the ports used and avoid conflicts between multiple instances on the same host. Default is 1 meaning an offset of 10.
- `SITE_DOMAIN`: Generated as localhost:x and cahnged manually for deployment.

Each deployment uses the same architecture but with isolated databases and configuration.

