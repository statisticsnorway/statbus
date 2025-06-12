# Architecture Overview

This document outlines the architecture of the Statbus application, focusing on the Docker Compose setup and the authentication flow.

## Supabase Libraries Usage

While the application uses direct PostgREST for database access and a custom authentication system, it still leverages Supabase client libraries for several reasons:

1. **Type Safety**: The Supabase client provides TypeScript types that match our database schema
2. **Consistent API**: The client offers a familiar, well-documented API for database operations
3. **Query Building**: The client includes utilities for building complex queries with proper escaping
4. **Error Handling**: Standardized error responses and handling patterns

IMPORTANT: We are NOT using Supabase as a service, only their client libraries.

Key distinctions:

- We use the Supabase client libraries (`@supabase/supabase-js`) but connect directly to our own PostgREST instance
- Authentication is handled entirely by our custom system, not Supabase Auth
- The client is configured with a dummy anon key since we use our own JWT-based auth system
- We extract the REST URL and fetch function from the client for direct API access when needed
- All data remains in our own PostgreSQL database, not in any Supabase-hosted service

This approach gives us the benefits of Supabase's type-safe client while maintaining full control over our authentication, database access, and data sovereignty.

## Docker Compose Services

The application is containerized using Docker Compose, orchestrating several services defined across multiple `docker-compose.*.yml` files. Profiles (`all`, `required`, `required_not_app`) allow selective startup of services.

1.  **`postgres` (Database)**
    *   Defined in `postgres/docker-compose.yml`.
    *   Uses a custom PostgreSQL 17 image built via `postgres/Dockerfile`.
    *   Includes numerous extensions:
        *   pgtap, plpgsql_check, pg_safeupdate, wal2json, pg_hashids, pgsql_http
        *   sql_saga, pg_stat_monitor, pg_repack, hypopg, index_advisor, pgjwt
    *   Initialized by `postgres/init-user-db.sh`, which:
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
        *   `/postgrest/*` requests are proxied to the `rest` service (PostgREST).
        *   All other requests are proxied to the `app` service (Next.js).
    *   Handles authentication cookie management:
        *   **Login (`/postgrest/rpc/login`):** Proxies to PostgREST. Forwards `Set-Cookie` headers from the PostgREST response (set by the `public.login` function) to the client.
        *   **Logout (`/postgrest/rpc/logout`):** Proxies to PostgREST. Forwards `Set-Cookie` headers from the PostgREST response (set by the `public.logout` function) to the client to clear cookies.
        *   **Refresh (`/postgrest/rpc/refresh`):** Proxies to PostgREST. This endpoint is called directly by the Next.js middleware (server-side) or the browser (client-side) during token refresh attempts. Caddy simply proxies the request.
        *   **AuthStatus (`/postgrest/rpc/auth_status`):** Proxies to PostgREST. Called by the Next.js app (server or client) to check current status.
        *   **Other API calls (`/postgrest/*`):** Proxies requests to PostgREST. For requests originating *from the browser*, Caddy doesn't need to modify headers as cookies are sent automatically. For requests originating *from the Next.js server*, the `getServerRestClient` function (used by server components/actions) reads the `statbus` cookie and sets the `Authorization: Bearer <token>` header itself before making the request through the proxy.

4.  **`app` (Frontend/Backend - Next.js)**
    *   Defined in `docker-compose.app.yml`.
    *   The main user-facing web application built from the `./app` directory.
    *   Configured with Supabase connection details and deployment slot information.
    *   Client-side state management is handled by Jotai.
    *   Environment variables include:
        *   Server-side PostgREST URL (`SERVER_REST_URL`)
        *   Logging configuration (`SEQ_SERVER_URL`, `SEQ_API_KEY`)
        *   Deployment slot information (`NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME`, `NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE`)
    *   Interacts with the API via Caddy (`/postgrest/*`).
    *   Depends on the database service being healthy before starting.

5.  **`worker` (Background Jobs)**
    *   Defined in `docker-compose.worker.yml`.
    *   Built from the `./cli` directory.
    *   Handles background tasks, interacting directly with the database.
    *   Configured with database connection details and logging settings.
    *   Depends on the database service being healthy before starting.

## Authentication Flow

Authentication relies on JWTs managed via PostgreSQL functions and PostgREST, with direct API calls from the browser. Client-side authentication state is managed using Jotai atoms.

1.  **Login:**
    *   User submits email/password to the Next.js app.
    *   App directly POSTs to `/postgrest/rpc/login` using a direct `fetch` call (via `loginAtom` in Jotai).
    *   PostgREST executes the `public.login(email, password)` function as the `anon` role.
    *   `public.login`:
        *   Verifies credentials against `auth.users`.
        *   If login fails (e.g., user not found, wrong password, email not confirmed, user deleted, null password submitted), it sets the HTTP response status to 401 using `PERFORM set_config('response.status', '401', true);`.
        *   If login is successful:
            *   Creates a record in `auth.refresh_sessions`.
            *   Generates an access token JWT and a refresh token JWT.
            *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers for the access token (`statbus-<slot>`) and refresh token (`statbus-<slot>-refresh`).
        *   Returns an `auth.auth_response` object in the JSON response body. This object contains:
            *   `is_authenticated` (boolean)
            *   User information (uid, sub, email, role, statbus_role, etc.) if authenticated.
            *   `error_code` (enum `auth.login_error_code`): This field is `NULL` on successful login. On failure, it contains one of the following values:
                *   `USER_NOT_FOUND`: The provided email does not correspond to an existing user.
                *   `USER_NOT_CONFIRMED_EMAIL`: The user exists but their email address has not been confirmed.
                *   `USER_DELETED`: The user account has been marked as deleted.
                *   `USER_MISSING_PASSWORD`: A null password was submitted.
                *   `WRONG_PASSWORD`: The password provided does not match the stored password for the user.
    *   The browser stores the cookies automatically if set.
    *   The Next.js app (via `loginAtom`) parses the `auth_response` from the `/rpc/login` call (including the `error_code` if present) and updates the global `authStatusAtom` (Jotai state).

2.  **Authenticated Requests:**
    *   **Client-Side Requests (Browser):**
        *   The browser automatically includes `statbus-<slot>` and `statbus-<slot>-refresh` cookies with requests to the API origin (`/postgrest/*`) due to `credentials: 'include'`.
        *   The `fetchWithAuthRefresh` utility (in `RestClientStore.ts`, used by `getBrowserRestClient`) wraps `fetch`:
            *   It relies on the browser sending cookies automatically.
            *   If a 401 response is received, it *internally and directly* calls the `/rpc/refresh` endpoint. The browser automatically sends the `statbus-<slot>-refresh` cookie with this internal call.
            *   If the internal refresh call is successful (PostgREST's `public.refresh` function sets new cookies via `Set-Cookie` headers and returns an `auth_response`), `fetchWithAuthRefresh` retries the original request. The `auth_response` from the internal refresh call is *not* directly used by `fetchWithAuthRefresh` to update Jotai state; the primary goal is cookie update. Jotai state (`authStatusAtom`) is typically updated by other mechanisms like `AppInitializer` or proactive checks.
    *   **Server-Side Requests (Next.js Server Components/Actions/Middleware):**
        *   The Next.js middleware (`app/src/middleware.ts`) runs first:
            *   It calls `AuthStore.handleServerAuth()` to check the status using the incoming request cookies.
            *   If the access token is invalid/missing but a refresh token exists, `handleServerAuth` attempts to refresh by calling `/rpc/refresh` directly. The `public.refresh` function returns an `auth_response`.
            *   `handleServerAuth` parses this `auth_response` to determine the new authentication status.
            *   If refresh is successful, the middleware updates the request headers (specifically the `cookie` header) for subsequent handlers within the *same request* and sets `Set-Cookie` headers on the outgoing response to update the browser's cookies.
            *   If authentication (initial or after refresh) fails, the middleware redirects to login.
        *   When code later calls `getServerRestClient()`:
            *   It reads the (potentially updated by middleware) `statbus` cookie from the current request context (e.g., via `next/headers` or passed cookies).
            *   It sets the `Authorization: Bearer <token>` header on the outgoing request to PostgREST.
    *   **PostgREST Processing:**
        *   PostgREST receives the request (either with cookies from the browser or an `Authorization` header from the Next.js server).
        *   It validates the JWT. If valid, it:
            *   Reads the `role` claim (user's email).
            *   Executes `SET LOCAL ROLE <email>` for the PostgreSQL transaction.
        *   Makes the JWT claims available via `current_setting('request.jwt.claims')`.
    *   The database operation proceeds with the permissions of the assigned role.
    *   Functions like `auth.uid()`, `auth.sub()`, `auth.email()`, and `auth.statbus_role()` can access JWT claims directly.

3.  **Logout:**
    *   App directly calls `/postgrest/rpc/logout` using a direct `fetch` call (via `logoutAtom` in Jotai).
    *   PostgREST executes `public.logout()` as the authenticated user.
    *   `public.logout`:
        *   Retrieves the user ID and possibly session ID from the current JWT claims.
        *   Deletes the relevant session(s) from `auth.refresh_session`.
        *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers that clear the auth cookies.
        *   Returns an `auth.auth_response` object (indicating unauthenticated status).
    *   The browser clears the cookies automatically.
    *   The Next.js app (via `logoutAtom`) parses the `auth_response` from the `/rpc/logout` call and updates the global `authStatusAtom`.

4.  **Token Refresh:**
    *   Token refresh is handled differently on client and server:
        *   **Client-Side (Browser - Reactive on 401):**
            *   Triggered when `fetchWithAuthRefresh` (used by `getBrowserRestClient`) receives a 401 Unauthorized response.
            *   `fetchWithAuthRefresh` *internally and directly* calls the `/rpc/refresh` endpoint. The browser automatically sends the `statbus-<slot>-refresh` cookie.
            *   PostgREST executes `public.refresh()`. This function sets new cookies via `Set-Cookie` headers and returns an `auth_response` object.
            *   The browser automatically updates its cookies based on the `Set-Cookie` headers.
            *   `fetchWithAuthRefresh` retries the original request. The `auth_response` from the internal refresh call is not used by `fetchWithAuthRefresh` to update Jotai state.
        *   **Server-Side (Middleware - Proactive/Reactive within Request):**
            *   Triggered within `app/src/middleware.ts` when `AuthStore.handleServerAuth()` is called and finds an invalid/missing access token but a valid refresh token cookie exists in the incoming request.
            *   `AuthStore.handleServerAuth()` directly `fetch`es the `/rpc/refresh` endpoint, manually adding the `Cookie: statbus-<slot>-refresh=...` header.
            *   PostgREST executes `public.refresh()`, which returns an `auth_response`.
            *   `AuthStore.handleServerAuth()` parses this `auth_response` and, if successful, uses the `response.cookies.set()` method (provided by the middleware) to stage the new cookies for the outgoing response to the browser.
            *   The middleware updates the *current request's* headers to reflect the new access token for subsequent processing within the same request lifecycle.
        *   **Proactive Refresh (Client-Side - Jotai):**
            *   The `clientSideRefreshAtom` (Jotai action atom) can be called to proactively refresh tokens.
            *   It calls the `/rpc/refresh` endpoint using the browser's `PostgrestClient` (which uses `fetchWithAuthRefresh`).
            *   PostgREST executes `public.refresh()`, returning an `auth_response`.
            *   The `clientSideRefreshAtom` parses this `auth_response` and updates the global `authStatusAtom`.
    *   The `public.refresh` PostgreSQL function:
        *   Extracts the refresh token (from cookies or passed argument).
        *   Validates the token, session, and user.
        *   Increments session version, updates timestamps.
        *   Generates a *new* access token JWT and a *new* refresh token JWT.
        *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers for the *new* tokens.
        *   Returns an `auth.auth_response` object.
        *   **Password Change Invalidation:** If the user's password has been changed, all their existing refresh sessions are deleted, causing subsequent refresh attempts with old tokens to fail.

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

## Views with SECURITY INVOKER

When creating views that need to respect row-level security policies, we use the `security_invoker=true` option:

```sql
CREATE OR REPLACE VIEW public.some_view
WITH (security_invoker=true) AS
SELECT * FROM private_schema.some_table;
```

This ensures that the view runs with the permissions of the calling user rather than the view owner. Without this option, row-level security policies on the underlying tables would not be applied correctly, as the view would run with the permissions of its owner (typically a privileged user).

The `security_invoker=true` option is particularly important for views that:
1. Expose data from schemas with restricted access
2. Need to respect row-level security policies
3. Are used for data access control where the user's identity matters

## Direct Database Access (Core Design Feature)

**A fundamental design principle of this system is that every application user (`auth.user`) also has a corresponding PostgreSQL role, allowing them direct database access (e.g., via `psql` or other clients) using their application credentials.** This is intentional and provides several benefits, while security is maintained through multiple layers:

1.  **Individual Roles:** Each user gets a unique PostgreSQL role named after their email.
2.  **Role Inheritance:** User roles `INHERIT` permissions from the base `authenticated` role and their specific `statbus_role` (e.g., `admin_user`, `regular_user`), ensuring a consistent permission model across API and direct access.
3.  **Row-Level Security (RLS):** Sensitive tables (like `auth.user`, `auth.api_key`) have RLS policies enforced (`FORCE ROW LEVEL SECURITY`). These policies restrict data visibility based on the user's identity (typically checked via `auth.uid()` which relies on `current_user`), ensuring users can only see or modify data they are explicitly allowed to, even with direct table access.
4.  **Standard Grants:** Access to schemas, tables, functions, and specific columns is controlled via standard PostgreSQL `GRANT` statements applied to the `authenticated` and `statbus_role` roles.

This layered approach ensures that even with direct database connections, users operate within the same security boundaries enforced by the API.

**Benefits of Direct Access:**

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

## API Keys for Scripting

For scenarios requiring non-interactive access (e.g., scripts, external services), long-lived API keys can be generated. These keys are JWTs, similar to access tokens, but with a much longer expiration time and potentially different claims.

1.  **Generation:**
    *   Authenticated users can call the `public.create_api_key(description text, duration interval)` function via the API (e.g., `POST /rest/rpc/create_api_key`).
    *   The function takes an optional description and duration (defaults to 1 year).
    *   It generates a JWT with `type: 'api_key'` and the specified expiration.
    *   The function returns the generated JWT string.
    *   A record is created in the `auth.api_key` table to track the key (identified by its `jti` claim), user, description, expiration, and revocation status.

2.  **Usage:**
    *   The generated API key (JWT string) should be used directly in the `Authorization: Bearer <api_key_jwt>` header for requests to the `/rest/*` API endpoints.
    *   PostgREST validates the JWT and sets the user context based on its claims (`role`, `sub`, etc.) just like a regular access token.
    *   **Revocation Check:** Before executing the main API query, PostgREST calls the `auth.check_api_key_revocation` function (configured via `PGRST_DB_PRE_REQUEST`). This function checks if the token type is `api_key` and if the corresponding record in `auth.api_key` (matched by `jti`) has been marked as revoked (`revoked_at IS NOT NULL`). If revoked, the function raises an error, blocking the request.

3.  **Management:**
    *   Users can list their own keys using `public.list_api_key()`.
    *   Users can revoke their own keys using `public.revoke_api_key(key_jti uuid)`. This sets the `revoked_at` timestamp in the `auth.api_key` table, immediately invalidating the key for future requests.
    *   Row-Level Security policies on `auth.api_key` ensure users can only manage their own keys.

4.  **Security:**
    *   API keys grant the same permissions as the user who created them.
    *   Due to their long lifespan, they should be stored securely and treated as sensitive credentials.
    *   Consider using shorter durations if possible and generating new keys periodically.
    *   Access to the `create_api_key` function can be restricted further by modifying the `GRANT EXECUTE` statement in the migration if needed (e.g., grant only to `admin_user`).
    *   Changing a user's password does *not* invalidate their existing API keys.
    *   **Restricted Privileges:** API keys are designed for programmatic access. They cannot be used to perform sensitive account management actions like changing the user's password or generating additional API keys. This is enforced by checks within the relevant PostgreSQL functions (`public.change_password`, `public.create_api_key`) which require a standard 'access' token type.

## Password Management

*   **User Changing Own Password:** Authenticated users can change their own password by calling `public.change_password(new_password text)`.
    *   This function requires a valid `access` token (not a refresh or API key), confirming the user is already logged in.
    *   It updates the `encrypted_password` in the `auth.user` table.
    *   Crucially, it deletes *all* existing refresh sessions for the user from `auth.refresh_session`, effectively logging them out of all other active sessions.
*   **Admin Changing User Password:** Administrators (`admin_user` role) can change any user's password by calling `public.admin_change_password(user_sub uuid, new_password text)`.
    *   This function requires the caller to have the `admin_user` role.
    *   It updates the target user's `encrypted_password`.
    *   It also deletes *all* existing refresh sessions for the target user.
*   **Password Reset (Future):** A typical password reset flow (request token via email, verify token, set new password) would need to be implemented separately. These functions would likely operate as the `anon` role initially.
