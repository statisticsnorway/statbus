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
        *   `/rest/*` requests are proxied to the `rest` service (PostgREST).
        *   All other requests are proxied to the `app` service (Next.js).
    *   Handles authentication cookie management:
        *   **Login (`/rest/rpc/login`):** Proxies to PostgREST. Forwards `Set-Cookie` headers from the PostgREST response (set by the `public.login` function) to the client.
        *   **Logout (`/rest/rpc/logout`):** Proxies to PostgREST. Forwards `Set-Cookie` headers from the PostgREST response (set by the `public.logout` function) to the client to clear cookies.
        *   **Refresh (`/rest/rpc/refresh`):** Proxies to PostgREST. This endpoint is called directly by the Next.js middleware (server-side) or the browser (client-side) during token refresh attempts. Caddy simply proxies the request.
        *   **AuthStatus (`/rest/rpc/auth_status`):** Proxies to PostgREST. Called by the Next.js app (server or client) to check current status.
        *   **Other API calls (`/rest/*`):** Proxies requests to PostgREST. For requests originating *from the browser*, Caddy doesn't need to modify headers as cookies are sent automatically. For requests originating *from the Next.js server*, the `getServerRestClient` function (used by server components/actions) reads the `statbus` cookie and sets the `Authorization: Bearer <token>` header itself before making the request through the proxy.

4.  **`app` (Frontend/Backend - Next.js)**
    *   Defined in `docker-compose.app.yml`.
    *   The main user-facing web application built from the `./app` directory.
    *   Configured with Supabase connection details and deployment slot information.
    *   Client-side state management is handled by Jotai.
    *   Environment variables include:
        *   Server-side PostgREST URL (`SERVER_REST_URL`)
        *   Logging configuration (`SEQ_SERVER_URL`, `SEQ_API_KEY`)
        *   Deployment slot information (`NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME`, `NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE`)
    *   Interacts with the API via Caddy (`/rest/*`).
    *   Depends on the database service being healthy before starting.

5.  **`worker` (Background Jobs)**
    *   Defined in `docker-compose.worker.yml`.
    *   Built from the `./cli` directory.
    *   Handles background tasks, interacting directly with the database.
    *   Configured with database connection details and logging settings.
    *   Depends on the database service being healthy before starting.

## Authentication Flow

Authentication relies on JWTs managed via PostgreSQL functions and PostgREST, with direct API calls from the browser. Client-side authentication state is managed using Jotai atoms. Mechanisms like an `AuthCrossTabSyncer` component ensure that authentication state changes (login, logout) are synchronized across multiple browser tabs.

1.  **Login:**
    *   User submits email/password to the Next.js app.
    *   App directly POSTs to `/rest/rpc/login` using a direct `fetch` call (via `loginAtom` in Jotai).
    *   PostgREST executes the `public.login(email, password)` function as the `anon` role.
    *   `public.login`:
        *   Verifies credentials against `auth.users`.
        *   If login fails (e.g., user not found, wrong password, email not confirmed, user deleted, null password submitted), it sets the HTTP response status to 401 using `PERFORM set_config('response.status', '401', true);`.
        *   If login is successful:
            *   Creates a record in `auth.refresh_sessions`.
            *   Generates an access token JWT and a refresh token JWT.
            *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers:
                *   **`statbus` (Access Token):**
                    *   `Path=/`
                    *   `HttpOnly=true`
                    *   `SameSite=Strict`
                    *   `Secure` (conditionally, if connection is HTTPS or `X-Forwarded-Proto: https`)
                    *   `Domain` (not explicitly set, defaults to the origin setting the cookie, which the browser interprets as the outermost domain like `localhost` or `dev.statbus.org`)
                *   **`statbus-refresh` (Refresh Token):**
                    *   `Path=/rest/rpc/refresh` (restricting it to the refresh endpoint)
                    *   `HttpOnly=true`
                    *   `SameSite=Strict`
                    *   `Secure` (conditionally, if connection is HTTPS or `X-Forwarded-Proto: https`)
                    *   `Domain` (not explicitly set, defaults to the origin setting the cookie)
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
    *   The Next.js app (via `loginAtom`) parses the `auth_response` from the `/rpc/login` call (including the `error_code` if present) and updates the global `authStatusAtom` (Jotai state). This update is also subject to cross-tab synchronization.

2.  **Authenticated Requests:**
    *   **Client-Side Requests (Browser):**
        *   The browser automatically includes the `statbus` cookie (Path=/) with requests to the API origin (`/rest/*`). The `statbus-refresh` cookie (Path=/rest/rpc/refresh) is only sent to the `/rest/rpc/refresh` endpoint. This is due to `credentials: 'include'` and the respective cookie paths.
        *   The `fetchWithAuthRefresh` utility (in `RestClientStore.ts`, used by `getBrowserRestClient`) wraps `fetch`:
            *   It relies on the browser sending cookies automatically.
            *   If a 401 response is received, it *internally and directly* calls the `/rest/rpc/refresh` endpoint. The browser automatically sends the `statbus-refresh` cookie with this internal call.
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
    *   App directly calls `/rest/rpc/logout` using a direct `fetch` call (via `logoutAtom` in Jotai).
    *   PostgREST executes `public.logout()` as the authenticated user.
    *   `public.logout`:
        *   Retrieves the user ID and possibly session ID from the current JWT claims.
        *   Deletes the relevant session(s) from `auth.refresh_session`.
        *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers that clear the auth cookies.
        *   Returns an `auth.auth_response` object (indicating unauthenticated status).
    *   The browser clears the cookies automatically.
    *   The Next.js app (via `logoutAtom`) parses the `auth_response` from the `/rpc/logout` call and updates the global `authStatusAtom`. This update is also subject to cross-tab synchronization.

4.  **Token Refresh:**
    *   Token refresh is handled differently on client and server:
        *   **Client-Side (Browser - Reactive on 401):**
            *   Triggered when `fetchWithAuthRefresh` (used by `getBrowserRestClient`) receives a 401 Unauthorized response.
            *   `fetchWithAuthRefresh` *internally and directly* calls the `/rest/rpc/refresh` endpoint. The browser automatically sends the `statbus-refresh` cookie.
            *   PostgREST executes `public.refresh()`. This function sets new cookies via `Set-Cookie` headers and returns an `auth_response` object.
            *   The browser automatically updates its cookies based on the `Set-Cookie` headers.
            *   `fetchWithAuthRefresh` retries the original request. The `auth_response` from the internal refresh call is not used by `fetchWithAuthRefresh` to update Jotai state.
        *   **Server-Side (Middleware - Proactive/Reactive within Request):**
            *   Triggered within `app/src/middleware.ts` when `AuthStore.handleServerAuth()` is called. `handleServerAuth` checks for an invalid/missing access token.
            *   **Limitation due to Cookie Path:** The `statbus-refresh` cookie is set with `Path=/rest/rpc/refresh`. Consequently, browsers will **not** send this cookie with requests to Next.js application paths (e.g., `/dashboard`, `/api/data`). Therefore, the Next.js middleware, when processing such requests, will typically **not** find the `statbus-refresh` cookie in the incoming request's headers.
            *   **Theoretical Mechanism (If Refresh Token Were Available to Middleware):** If the middleware *could* obtain the refresh token (e.g., if the cookie path allowed it or through other means not currently implemented), the described mechanism would be:
                *   `AuthStore.handleServerAuth()` directly `fetch`es the `/rest/rpc/refresh` endpoint, manually adding the `Cookie: statbus-refresh=...` header.
                *   PostgREST executes `public.refresh()`, which returns an `auth_response`.
                *   `AuthStore.handleServerAuth()` parses this `auth_response` and, if successful, uses the `response.cookies.set()` method (provided by the middleware) to stage the new cookies for the outgoing response to the browser.
                *   The middleware updates the *current request's* headers to reflect the new access token for subsequent processing within the same request lifecycle.
            *   **Current Practicality:** Due to the `statbus-refresh` cookie's `Path=/rest/rpc/refresh` restriction, this server-side refresh mechanism by the middleware is effectively not utilized for typical Next.js page/API requests, as the middleware cannot access the necessary refresh token from the browser's request to such paths. Token refresh is therefore primarily a client-side responsibility.
        *   **Proactive Refresh (Client-Side - `AppInitializer` / Jotai):**
            *   A proactive client-side refresh is attempted during application initialization, typically orchestrated by a component like `AppInitializer`.
            *   This occurs after the initial authentication status check (`authStatusCoreAtom`) has resolved and if the user is found to be unauthenticated (`authStatusAtom.isAuthenticated` is false) and not in a loading state.
            *   To prevent loops, this proactive refresh is generally attempted only once per page load or app initialization under these specific conditions.
            *   The `clientSideRefreshAtom` (Jotai action atom) is invoked to make the `POST` request to `/rest/rpc/refresh`. The browser automatically sends the `statbus-refresh` cookie if available and its path matches.
            *   If the refresh is successful (HTTP 200 from `/rpc/refresh`), the browser updates its cookies. `AppInitializer` (or the logic handling the refresh response) then triggers a re-evaluation of the global authentication state (e.g., by `set(authStatusCoreAtom)`), which updates `authStatusAtom`.
            *   If the refresh fails (e.g., HTTP 401), the global authentication state is similarly updated to reflect the continued unauthenticated status.
    *   The `public.refresh` PostgreSQL function:
        *   Extracts the refresh token from cookies.
        *   Validates the token, session, and user.
        *   If any validation fails (e.g., no token, invalid token type, user not found, session invalid/superseded):
            *   It clears authentication cookies using `auth.clear_auth_cookies()`.
            *   It resets the session context using `auth.reset_session_context()`.
            *   It sets the HTTP response status to 401 using `PERFORM set_config('response.status', '401', true);`.
            *   It returns an `auth.auth_response` object with `is_authenticated: false` and a specific `error_code` (from `auth.login_error_code` enum):
                *   `REFRESH_NO_TOKEN_COOKIE`
                *   `REFRESH_INVALID_TOKEN_TYPE`
                *   `REFRESH_USER_NOT_FOUND_OR_DELETED`
                *   `REFRESH_SESSION_INVALID_OR_SUPERSEDED`
        *   If validation is successful:
            *   Increments session version, updates timestamps, IP address, and user agent in `auth.refresh_session`.
            *   Generates a *new* access token JWT and a *new* refresh token JWT.
            *   Uses `set_config('response.headers', ...)` to create `Set-Cookie` headers for the *new* tokens, with attributes identical to those set during login:
                *   **`statbus` (New Access Token):** `Path=/`, `HttpOnly`, `SameSite=Strict`, conditional `Secure`, default `Domain`.
                *   **`statbus-refresh` (New Refresh Token):** `Path=/rest/rpc/refresh`, `HttpOnly`, `SameSite=Strict`, conditional `Secure`, default `Domain`.
            *   Returns an `auth.auth_response` object indicating successful authentication and providing new user/token details.
        *   **Password Change Invalidation:** If the user's password has been changed, all their existing refresh sessions are deleted. Subsequent refresh attempts with old tokens will fail, typically resulting in `REFRESH_SESSION_INVALID_OR_SUPERSEDED`.

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

### Troubleshooting Inter-Service Communication & Authentication

Debugging sessions (June 2025) for authentication issues between the Next.js app, the internal Caddy proxy (`proxy:80`), and PostgREST (`rest:3000`) revealed several key insights:

1.  **Internal Caddy `Host` Header Matching:**
    *   When the Next.js application (service `app`) makes internal HTTP requests to the internal Caddy proxy (service `proxy`, e.g., `http://proxy/rest/...`), the `Host` header of these requests, as seen by the `proxy` Caddy instance, will be the hostname used in the URL (e.g., `proxy`).
    *   Attempts by the Next.js application to explicitly set a different `Host` header (e.g., `Host: dev.statbus.org`) in its `fetch` calls to `http://proxy/...` may not alter the `Host` header actually processed by the internal Caddy for its site matching. HTTP client libraries (like Node.js `fetch`) often derive the `Host` header from the URL's authority component.
    *   **Problem Manifestation:** If the internal Caddy's Caddyfile does not have a site block that explicitly matches `Host: proxy` (or the internal service name used), it may not correctly route these internal requests to the intended upstream (e.g., PostgREST). This can result in "NOP" (No Operation) logs from Caddy, where Caddy serves a default empty 200 OK or another status without proxying.
    *   **Solution:** The Caddyfile for the internal proxy service (`proxy:80`) must include a site block that matches requests to its internal hostname (e.g., `http://proxy:80, http://proxy`). Within this block, specific paths (like `/rest/*`) should then be routed to the correct upstream (e.g., `rest:3000`). An additional matcher using `header X-Forwarded-Host <external_domain>` can be used within this internal host block to ensure that requests are only proxied if they were originally intended for the correct external domain.

2.  **`X-Forwarded-*` Headers:**
    *   When the Next.js application makes server-side calls to internal services (like `http://proxy/rest/...`), it's crucial for it to set appropriate `X-Forwarded-For`, `X-Forwarded-Proto`, and `X-Forwarded-Host` headers. These headers provide the internal Caddy proxy and the ultimate upstream (PostgREST/SQL functions) with the context of the original client request.
    *   The `X-Forwarded-Host` header is particularly important if the internal Caddy proxy uses it in matchers (as implemented in June 2025) to route requests for `Host: proxy` only if they are intended for a specific external domain.
    *   The `X-Forwarded-Proto` header is important if PostgREST or SQL functions have logic that depends on whether the original connection was HTTPS (e.g., for setting `Secure` cookie attributes).

3.  **Diagnosing Empty Responses from Internal Calls:**
    *   If internal calls from Next.js to PostgREST (via `http://proxy:80`) return HTTP 200 OK but with an empty body (`Content-Length: 0`) or `data: null` in the application:
        *   First, check the internal Caddy (`proxy:80`) logs. "NOP" logs indicate the request wasn't proxied to PostgREST, likely due to a `Host` mismatch in the Caddyfile.
        *   If the internal Caddy *is* proxying the request (i.e., no "NOP" log, and logs show an upstream roundtrip to `rest:3000`), then the issue might be with PostgREST or the SQL function itself (e.g., not receiving expected headers/claims and thus returning an empty valid response).
        *   The `/api/auth_test` endpoint in Next.js was instrumental in diagnosing this by showing what headers Next.js sent and what response (including `Content-Length`) it received from internal calls.

4.  **`postgrest-js` Server-Side Header Forwarding:**
    *   When using `getServerRestClient()` (which utilizes `postgrest-js`) for server-side calls from Next.js to the internal proxy, ensure that the underlying `fetch` mechanism is configured to forward necessary headers like `X-Forwarded-Host`, `X-Forwarded-Proto`, and `X-Forwarded-For`. If `postgrest-js` does not do this by default, its `fetch` option may need to be customized to add these headers, similar to how direct `fetch` calls are augmented in `/api/auth_test`. This is crucial if the internal Caddy relies on these headers for routing decisions (e.g., the `header X-Forwarded-Host <%= @domain %>` matcher).

These insights highlight the importance of correctly configuring the internal Caddy proxy to handle requests based on the actual `Host` header it receives for internal service-to-service communication, and ensuring that necessary context (like original `X-Forwarded-*` headers) is propagated by the calling application (Next.js) if intermediate proxies or upstreams rely on them.

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
    
1. When a user is created in `auth.user`, a trigger function (`auth.sync_user_credentials_and_roles()`) automatically:
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
    *   Users can list their own keys using the `public.api_key` view.
    *   Users can revoke their own keys using `public.revoke_api_key(key_jti uuid)`. This sets the `revoked_at` timestamp in the `auth.api_key` table, immediately invalidating the key for future requests.
    *   Row-Level Security policies on `auth.api_key` (and the `security_invoker` property of the `public.api_key` view) ensure users can only manage their own keys.

4.  **Security:**
    *   API keys grant the same permissions as the user who created them.
    *   Due to their long lifespan, they should be stored securely and treated as sensitive credentials.
    *   Consider using shorter durations if possible and generating new keys periodically.
    *   Access to the `create_api_key` function can be restricted further by modifying the `GRANT EXECUTE` statement in the migration if needed (e.g., grant only to `admin_user`).
    *   Changing a user's password does *not* invalidate their existing API keys.
    *   **Restricted Privileges:** API keys are designed for programmatic access. They cannot be used to perform sensitive account management actions like changing the user's password. This is enforced by a check within `public.change_password` which requires a standard 'access' token type. Currently, `public.create_api_key` does not enforce such a check, meaning an API key could potentially be used to create other API keys if its associated user role has execute permission on `public.create_api_key`.

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
