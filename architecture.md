# Architecture Overview

This document outlines the architecture of the Statbus application, focusing on the Docker Compose setup and the authentication flow.

## Docker Compose Services

The application is containerized using Docker Compose, orchestrating several services defined across multiple `docker-compose.*.yml` files. Profiles (`all`, `required`, `required_not_app`) allow selective startup of services.

1.  **`postgres` (Database)**
    *   Defined in `docker-postgres/docker-compose.yml`.
    *   Uses a custom PostgreSQL 17 image built via `docker-postgres/Dockerfile`.
    *   Includes numerous extensions:
        *   pgtap, plpgsql_check, pg_safeupdate, wal2json, pg_hashids, pgsql_http
        *   sql_saga, pg_stat_monitor, pg_repack, hypopg, index_advisor, pgjwt
    *   Initialized by `docker-postgres/init-user-db.sh`, which:
        *   Creates a template database (`template_statbus`) with required extensions (pg_trgm, pgcrypto, etc.).
        *   Creates the main application database (`statbus_development`) and a test database (`statbus_test`).
        *   Sets up core roles: `authenticator` (for PostgREST login), `anon` (unauthenticated users), `authenticated` (base role for logged-in users).
        *   Creates application-specific roles: `admin_user`, `regular_user`, `restricted_user`, `external_user`.
        *   Creates the `auth` schema with `user` and `refresh_sessions` tables.
        *   Grants initial permissions.
    *   Configured via environment variables and command-line arguments for performance tuning.
    *   Data is persisted in a volume at `./volumes/db/data`.
    *   Uses custom PostgreSQL configuration files:
        *   `postgresql.conf` for general settings:
            *   Memory settings: shared_buffers (1GB), work_mem (1GB), maintenance_work_mem (1GB)
            *   WAL settings: wal_level=logical for wal2json, synchronous_commit=off for performance
            *   Query tuning: effective_cache_size (3GB), hash_mem_multiplier (2.0)
            *   Preloaded extensions: pg_stat_monitor, wal2json
        *   `pg_hba.conf` for client authentication:
            *   Allows local connections with md5 password authentication
            *   Allows connections from Docker networks (172.16.0.0/12, 192.168.0.0/16, 10.0.0.0/8)
            *   Allows connections from anywhere (0.0.0.0/0) for development purposes

2.  **`rest` (API Layer - PostgREST)**
    *   Defined in `docker-compose.rest.yml`.
    *   Uses the official `postgrest/postgrest` image (v12.2.0).
    *   Connects to the `postgres` service using the `authenticator` role.
    *   Exposes the `public` database schema via a RESTful API.
    *   Configured for JWT authentication:
        *   Uses `anon` as the default role for unauthenticated requests.
        *   Validates JWTs provided in the `Authorization: Bearer` header using `PGRST_JWT_SECRET`.
        *   Switches the database session role based on the `role` claim in valid JWTs.
            *   The `role` claim must contain a valid PostgreSQL role name (user's email).
            *   Additional claims like `statbus_role` are used for application-level permissions.
        *   Makes JWT claims available to SQL functions via `current_setting('request.jwt.claims')`.
        *   Passes JWT configuration (`PGRST_APP_SETTINGS_JWT_SECRET`, `PGRST_APP_SETTINGS_ACCESS_JWT_EXP`, `PGRST_APP_SETTINGS_REFRESH_JWT_EXP`) and the deployment slot code (`PGRST_DB_CONFIG`) to PostgreSQL as runtime settings (`app.settings.*`).
        *   Enables aggregates for group by counting with `PGRST_DB_AGGREGATES_ENABLED`.

3.  **`caddy` (Web Server / Reverse Proxy)**
    *   Defined in `docker-compose.caddy.yml`.
    *   Uses the official `caddy:2.7-alpine` image.
    *   Acts as the main entry point for web traffic (ports 80/443).
    *   Configured via `caddy/Caddyfile`.
    *   Routes requests:
        *   `/api/*` requests are proxied to the `rest` service (PostgREST).
        *   All other requests are proxied to the `app` service (Next.js).
    *   Handles authentication cookie management:
        *   **Login (`/api/rpc/login`):** Proxies to PostgREST. Forwards `Set-Cookie` headers from the PostgREST response (set by the `public.login` function) to the client.
        *   **Logout (`/api/rpc/logout`):** Proxies to PostgREST (adding `Authorization` header). On response, explicitly sends headers to clear auth cookies.
        *   **Refresh (`/api/rpc/refresh`):** Proxies to PostgREST, using the refresh token cookie as the Authorization header.
        *   **Other API calls (`/api/*`):** Extracts the JWT from the `statbus-<slot>` cookie and adds it as an `Authorization: Bearer <token>` header before proxying to PostgREST.

4.  **`app` (Frontend/Backend - Next.js)**
    *   Defined in `docker-compose.app.yml`.
    *   The main user-facing web application built from the `./app` directory.
    *   Configured with Supabase connection details and deployment slot information.
    *   Environment variables include:
        *   Supabase configuration (`NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_BROWSER_SUPABASE_URL`)
        *   Server-side Supabase URL (`SERVER_SUPABASE_URL`)
        *   Logging configuration (`SEQ_SERVER_URL`, `SEQ_API_KEY`)
        *   Deployment slot information (`NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME`, `NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE`)
    *   Interacts with the API via Caddy (`/api/*`).
    *   Depends on the database service being healthy before starting.

5.  **`worker` (Background Jobs)**
    *   Defined in `docker-compose.worker.yml`.
    *   Built from the `./cli` directory.
    *   Handles background tasks, interacting directly with the database.
    *   Configured with database connection details and logging settings.
    *   Depends on the database service being healthy before starting.

## Authentication Flow

Authentication relies on JWTs managed via PostgreSQL functions, PostgREST, and Caddy working together.

1.  **Login:**
    *   User submits email/password to the Next.js app.
    *   App POSTs to `/api/rpc/login`.
    *   Caddy proxies the request to PostgREST (`/rpc/login`).
    *   PostgREST executes the `public.login(email, password)` function as the `anon` role.
    *   `public.login`:
        *   Verifies credentials against `auth.users`.
        *   Creates a record in `auth.refresh_sessions`.
        *   Generates an access token JWT with these critical claims:
            *   `role`: Set to the user's email (matches PostgreSQL role name)
            *   `statbus_role`: User's application role (admin_user, regular_user, etc.) as text
            *   `sub`: User's UUID as text
            *   `email`: User's email address
            *   `type`: "access"
            *   `iat`: Issued at timestamp
            *   `exp`: Expiration timestamp
        *   Generates a refresh token JWT with similar claims plus:
            *   `jti`: Session UUID as text
            *   `version`: Session version (for invalidation)
            *   `ip`: Client IP address
            *   `ua_hash`: User agent hash (for verification)
        *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers for the access token (`statbus-<slot>`) and refresh token (`statbus-<slot>-refresh`). The `<slot>` is determined by `app.settings.deployment_slot_code`.
        *   Returns tokens and user info in the JSON response body.
    *   PostgREST sends the response, including the `Set-Cookie` headers, back through Caddy.
    *   Caddy forwards the response to the browser, which stores the cookies.

2.  **Authenticated Requests:**
    *   Browser automatically includes the `statbus-<slot>` cookie with requests to the API (`/api/*`).
    *   Caddy intercepts the request.
    *   Caddy reads the access token cookie value and sets the `Authorization: Bearer <token>` header.
    *   Caddy proxies the modified request to PostgREST, adding headers for:
        *   `Host`: Original host
        *   `X-Real-IP`: Client IP
        *   `X-Forwarded-For`: Client IP
        *   `X-Forwarded-Proto`: Original scheme (http/https)
    *   PostgREST validates the JWT. If valid, it:
        *   Reads the `role` claim (user's email)
        *   Executes `SET LOCAL ROLE <email>` for the PostgreSQL transaction
        *   Makes the JWT claims available via `current_setting('request.jwt.claims')`
    *   The database operation proceeds with the permissions of the assigned role.
    *   Functions like `auth.uid()`, `auth.email()`, and `auth.statbus_role()` can access JWT claims.

3.  **Logout:**
    *   App calls `/api/rpc/logout`.
    *   Caddy adds the `Authorization` header (from the cookie) and proxies to PostgREST (`/rpc/logout`).
    *   PostgREST executes `public.logout()` as the authenticated user.
    *   `public.logout`:
        *   Retrieves the user ID and possibly session ID from the current JWT claims (`current_setting('request.jwt.claims', true)`).
        *   If it's a refresh token, deletes the specific session from `auth.refresh_session`.
        *   If it's an access token, optionally deletes all sessions for the user.
    *   PostgREST sends a success response back through Caddy.
    *   Caddy's configuration for `/api/rpc/logout` includes a `handle_response` block that explicitly adds `Set-Cookie` headers to expire/clear the `statbus-<slot>` and `statbus-<slot>-refresh` cookies in the browser.

4.  **Token Refresh:**
    *   When the JWT (`statbus-<slot>`) expires, the client-side application should detect this (e.g., via API errors or proactive checking).
    *   The browser automatically sends both the (potentially expired) `statbus-<slot>` cookie and the `statbus-<slot>-refresh` cookie when the client POSTs to `/api/rpc/refresh`.
    *   Caddy proxies the request to PostgREST (`/rpc/refresh`).
        *   Caddy extracts the refresh token from the cookie and sets it as the `Authorization` header before forwarding to PostgREST.
    *   PostgREST validates the refresh token JWT and executes `public.refresh()`.
    *   `public.refresh`:
        *   Extracts the refresh token from cookies using `auth.extract_refresh_token_from_cookies()`.
        *   Validates the token and extracts claims.
        *   Verifies the session exists in `auth.refresh_session` with matching user ID and version.
        *   Verifies the user agent hash matches.
        *   Increments the session version and updates last used time and expiry.
        *   Generates a *new* access token JWT and a *new* refresh token JWT with updated version.
        *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers for the *new* tokens.
    *   PostgREST sends the response (with new tokens in the body and new `Set-Cookie` headers) back through Caddy.
    *   Caddy forwards the response to the browser, which updates the cookies.

## Key Configuration Points

*   **JWT Secrets:** 
    * JWT secret must be consistent between PostgREST and PostgreSQL.
    * PostgREST uses `PGRST_JWT_SECRET` for JWT validation.
    * PostgREST passes the JWT secret to PostgreSQL via `PGRST_APP_SETTINGS_JWT_SECRET`, which becomes available as `app.settings.jwt_secret` in the database.
    * Both access and refresh tokens use the same JWT secret for consistency, as configured in `docker-compose.rest.yml`.
    * The JWT secret is passed from the environment variable `JWT_SECRET` to both PostgreSQL and PostgREST.
    * Default expiry times: 
      * Access token: 3600 seconds (1 hour) via `app.settings.access_jwt_exp`
      * Refresh token: 2592000 seconds (30 days) via `app.settings.refresh_jwt_exp`
*   **JWT Claims Structure:**
    * The `role` claim must be the user's email, which corresponds to a PostgreSQL role.
    * The `statbus_role` claim must be cast to text when included in the JWT.
    * All UUID values must be converted to text strings in the JWT.
    * PostgREST uses the `role` claim directly (default behavior) to set the PostgreSQL role.
*   **Roles:** 
    * `authenticator` (PostgREST connection)
    * `anon` (unauthenticated API access)
    * `authenticated` (base logged-in access)
    * `admin_user`, `regular_user`, `restricted_user`, `external_user` (application role types)
    * `<email>` (per-user roles created by triggers, granted one of the application roles)
*   **Environment Variables:**
    * `NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE`: Used to identify the deployment environment (dev, test, prod)
    * `JWT_SECRET`: Shared secret for JWT signing and verification
    * `POSTGRES_APP_DB`: Database name, typically includes the deployment slot code
    * `POSTGRES_APP_USER`: Database user for application access
    * `POSTGRES_APP_PASSWORD`: Database password for application access

## Direct Database Access

The authentication system is designed to allow users direct database access via psql or other PostgreSQL clients, in addition to API access through the application. This provides several benefits:

1. **Advanced Data Analysis**: Power users can run complex SQL queries directly against the database.
2. **Debugging and Support**: Administrators can troubleshoot issues by examining data directly.
3. **Integration with External Tools**: BI tools, data science notebooks, and other systems can connect using user credentials.
4. **Emergency Access**: If the API layer is unavailable, authorized users can still access data.

### How It Works

1. When a user is created in `auth.user`, a trigger function (`auth.create_user_role()`) automatically:
   * Creates a PostgreSQL role with the same name as the user's email
   * Grants the `authenticated` role to this user role
   * Grants the appropriate statbus role (`admin_user`, `regular_user`, etc.) to the user role
   * Sets the database password for this role to match the user's application password

2. Users can then connect to the database directly using:
   * Username: their email address
   * Password: their application password
   * Database: the application database (e.g., `statbus_development`)

3. The user's database permissions are determined by:
   * The `authenticated` role (base permissions)
   * Their specific statbus role (e.g., `admin_user` has more permissions than `restricted_user`)
   * Any additional custom grants made to their specific role
   
   IMPORTANT: User roles are created with the INHERIT attribute (PostgreSQL default) which is essential
   for the permission hierarchy to work correctly. This ensures that when users connect with their email
   role, they automatically inherit all permissions from both the `authenticated` role and their specific
   statbus role. Without INHERIT, the role hierarchy would break and users would not have the expected
   permissions when connecting directly to the database.

4. When a user changes their password in the application, their database role password is updated automatically.

5. If a user is deleted, a trigger (`auth.drop_user_role_trigger`) removes their database role.

This approach maintains a single source of truth for authentication while providing flexibility in how users interact with the system.

## Date Range Operations

### OVERLAPS vs daterange

PostgreSQL provides two main ways to check if date ranges overlap:

1. **OVERLAPS operator**: `(start1, end1) OVERLAPS (start2, end2)`
2. **Range operator**: `daterange(start1, end1, bounds) && daterange(start2, end2, bounds)`

The key difference is how boundaries are handled:

- **OVERLAPS** implicitly uses inclusive-inclusive `[]` boundaries
- **daterange** allows explicit boundary specification:
  - `[]`: inclusive-inclusive (default)
  - `[)`: inclusive-exclusive
  - `(]`: exclusive-inclusive
  - `()`: exclusive-exclusive

### Naming Convention Impact

When using column names like:
- `valid_from`: Implies an inclusive lower bound (the range starts AT this date)
- `valid_after`: Implies an exclusive lower bound (the range starts AFTER this date)

Therefore:
- `(valid_from, valid_to) OVERLAPS (...)` is equivalent to `daterange(valid_from, valid_to, '[]') && daterange(...)`
- `(valid_after, valid_to) OVERLAPS (...)` is logically equivalent to `daterange(valid_after, valid_to, '(]') && daterange(...)`

This naming convention helps clarify the intended boundary behavior in the database schema.

#### Example: Starting from January 1, 2023

If you want a range that starts from January 1, 2023 (inclusive):
- Using `valid_from`: Set `valid_from = '2023-01-01'`
- Using `valid_after`: Set `valid_after = '2022-12-31'` (the day before)

This is because:
- `valid_from = '2023-01-01'` means "valid starting on January 1, 2023"
- `valid_after = '2022-12-31'` means "valid after December 31, 2022" (which is the same as "from January 1, 2023")

### Performance Considerations

When choosing between OVERLAPS and daterange operators, consider these performance factors:

1. **Query Optimizer Behavior**: 
   - The PostgreSQL optimizer may handle OVERLAPS and daterange differently
   - OVERLAPS is a built-in operator that may have specific optimizations
   - daterange with && uses the GiST index infrastructure

2. **Infinity Handling**:
   - Special care is needed when using `-infinity` and `infinity` values
   - Comparisons like `valid_after < '-infinity'` will always be false
   - Using COALESCE or explicit equality checks can help handle edge cases

3. **Indexing Strategy**:
   - For daterange queries, consider creating a GiST index on the range: `CREATE INDEX ON table USING GIST (daterange(valid_after, valid_to, '(]'))`
   - For OVERLAPS queries, consider indexes on the individual columns

4. **Boundary Type Impact**:
   - The choice of boundary type ('[]', '(]', '[)', '()') affects both correctness and performance
   - Match the boundary type to your column naming convention for clarity

The performance tests in speed.sql provide empirical data on which approach performs better for specific query patterns in this database.
