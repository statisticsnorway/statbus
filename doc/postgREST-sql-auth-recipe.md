# Users with Distinct PostgreSQL Roles and Integrated RLS App Roles

This guide outlines a user management strategy for PostgREST where each application user is mapped to a distinct PostgreSQL role. This approach ensures that permissions and Row Level Security (RLS) are consistently applied, whether access is through the PostgREST API or direct database connections. It leverages PostgreSQL's robust security model to provide fine-grained access control.

## Core Concepts

1.  **User's Email as PostgreSQL Role**: Each application user's email address (e.g., `user@example.com`) becomes their unique PostgreSQL role name. This role defines the user's specific permissions.
2.  **Application-Level Roles (`statbus_role`)**: A `public.statbus_role` ENUM (e.g., `admin_user`, `regular_user`) defines broader application-level permissions. The user's PostgreSQL role (their email) is granted membership in one of these `statbus_role` PostgreSQL roles (e.g., `GRANT regular_user TO "user@example.com"`).
3.  **Application-Managed Credentials & Role Sync**: User registration and primary authentication are handled by SQL functions. User metadata, including their `email` and chosen `statbus_role`, is stored in `auth.user`. Triggers (`auth.sync_user_credentials_and_roles`) automatically create/manage the corresponding PostgreSQL role (named after the email), set its password, and grant it membership in the appropriate `statbus_role` and the `authenticated` role.
4.  **JWT for API Authentication**: Upon successful login via `public.login`, a JWT is issued. The `role` claim in this JWT contains the user's email (their PostgreSQL role name). Other claims like `sub` (UUID), `uid` (integer ID), and `statbus_role` are also included.
5.  **PostgREST Role Switching**: PostgREST, using its `authenticator` role, performs a `SET ROLE` to the PostgreSQL role specified in the JWT's `role` claim (i.e., `SET ROLE "user@example.com"`). All subsequent database operations for that request occur as this specific user role.
6.  **Unified RLS**: Row Level Security policies are defined using `current_user` (which will be the user's email, e.g., `"user@example.com"`) and helper functions like `auth.uid()` or `auth.statbus_role()` to check application-level roles. This ensures consistent data access rules across API and direct DB access.

## Implementation Steps

### 1. Schema and Basic Roles Setup

We'll use an `auth` schema for user management and a `public.statbus_role` ENUM for application-level roles.

```sql
-- Create auth schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS auth;

-- Define application-level roles
CREATE TYPE public.statbus_role AS ENUM('admin_user','regular_user', 'restricted_user', 'external_user');

-- Create PostgreSQL roles corresponding to each statbus_role
-- These act as group roles. Individual user roles (their emails) will be members of one of these.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN CREATE ROLE admin_user; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN CREATE ROLE regular_user; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN CREATE ROLE restricted_user; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'external_user') THEN CREATE ROLE external_user; END IF;
  
  -- Set up role hierarchy (e.g., admin_user inherits permissions of regular_user)
  GRANT regular_user TO admin_user;
  GRANT restricted_user TO regular_user;
  GRANT external_user TO restricted_user;
END
$$;

-- Role that PostgREST uses to connect to the database
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'your_secure_password';

-- Role for unauthenticated requests (e.g., to access the login function)
CREATE ROLE anon NOINHERIT;
GRANT anon TO authenticator; -- Authenticator can impersonate anon

-- General role for all authenticated users. Individual user roles (their emails)
-- will be granted membership in 'authenticated'.
CREATE ROLE authenticated NOINHERIT;
GRANT authenticated TO authenticator; -- Authenticator can impersonate authenticated users generally before specific role switch

-- Grant the statbus_role group roles to 'authenticated' if they should also have base authenticated permissions.
-- Or, grant 'authenticated' to each statbus_role if statbus_roles are more fundamental.
-- The provided migrations grant 'authenticated' to individual user roles directly.
-- And grant individual user roles to 'authenticator'.
-- And grant specific 'statbus_role' (e.g. 'regular_user') to the individual user role.
```

Configure PostgREST (e.g., in `postgrest.conf` or environment variables):
- `db-uri = "postgres://authenticator:your_secure_password@localhost:5432/your_db"`
- `db-anon-role = "anon"`
- `jwt-secret = "your-very-secure-and-long-jwt-secret"` (must be at least 32 characters, ideally stored in `app.settings.jwt_secret` GUC)
- `db-pre-request = "auth.check_api_key_revocation"` (Optional, if using API keys as described in migrations)

### 2. User Storage

The `auth.user` table stores application user information. The user's email is unique and also serves as the basis for their PostgreSQL role name.

```sql
CREATE TABLE IF NOT EXISTS auth.user (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sub uuid UNIQUE NOT NULL DEFAULT gen_random_uuid(), -- Stable unique identifier
  email text UNIQUE NOT NULL, -- User's email, also used as their PostgreSQL role name
  password text, -- Temporary storage for plain text password, cleared by trigger
  encrypted_password text NOT NULL, -- Stores the hashed password
  statbus_role public.statbus_role NOT NULL DEFAULT 'regular_user', -- Application-level role
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_sign_in_at timestamptz,
  email_confirmed_at timestamptz,
  deleted_at timestamptz
);

-- Helper functions to get current user's identifiers based on current_user (their email role)
CREATE OR REPLACE FUNCTION auth.sub() RETURNS UUID LANGUAGE SQL STABLE SECURITY INVOKER AS
$$ SELECT sub FROM auth.user WHERE email = current_user; $$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS INTEGER LANGUAGE SQL STABLE SECURITY INVOKER AS
$$ SELECT id FROM auth.user WHERE email = current_user; $$;

CREATE OR REPLACE FUNCTION auth.statbus_role() RETURNS public.statbus_role LANGUAGE SQL STABLE SECURITY INVOKER AS
$$ SELECT statbus_role FROM auth.user WHERE email = current_user; $$;

GRANT EXECUTE ON FUNCTION auth.sub() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.statbus_role() TO authenticated, anon;
```
Ensure the `pgcrypto` extension is available (e.g., `CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA public;`). The `public.crypt` and `public.gen_salt` functions are used by triggers.

### 3. User Registration and PostgreSQL Role Synchronization

User registration is handled by `public.user_create`. Crucially, two `BEFORE INSERT OR UPDATE` triggers on `auth.user` manage PostgreSQL role creation, password synchronization, and permission assignments:
1.  `auth.check_role_permission` (SECURITY INVOKER): Ensures the calling user has permission to assign the target `statbus_role`.
2.  `auth.sync_user_credentials_and_roles` (SECURITY DEFINER):
    *   Encrypts the plain text password from `auth.user.password` into `auth.user.encrypted_password` and then nullifies `auth.user.password`.
    *   Creates a PostgreSQL role named after `NEW.email` if it doesn't exist, with `LOGIN INHERIT` attributes.
    *   Sets the PostgreSQL role's password to match the user's application password.
    *   Grants the new role (e.g., `"user@example.com"`) to `authenticator` (allowing PostgREST to `SET ROLE`).
    *   Grants `authenticated` to the new role.
    *   Grants the specified `NEW.statbus_role` (e.g., `regular_user`) to the new role.
    *   Handles renaming of the PostgreSQL role if the user's email changes.
    *   Handles changes in `statbus_role` by revoking the old and granting the new `statbus_role` to the user's PostgreSQL role.

```sql
-- Simplified public function to create a user. RLS on auth.user controls who can insert.
CREATE FUNCTION public.user_create(
    p_email text,
    p_statbus_role public.statbus_role,
    p_password text DEFAULT NULL -- If NULL, a random one is generated
) RETURNS TABLE (email text, password text) -- Returns email and plain password (if generated)
LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE
    v_password text;
    v_email text := lower(p_email);
BEGIN
    IF p_password IS NULL THEN
        SELECT string_agg(substr('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*', ceil(random()*75)::integer, 1), '')
        FROM generate_series(1, 12) INTO v_password;
    ELSE
        v_password := p_password;
    END IF;

    INSERT INTO auth.user (email, password, statbus_role, email_confirmed_at)
    VALUES (v_email, v_password, p_statbus_role, clock_timestamp())
    ON CONFLICT (email) DO UPDATE SET
        password = EXCLUDED.password,
        statbus_role = EXCLUDED.statbus_role,
        updated_at = clock_timestamp();
    -- The actual password hashing and role creation happens in the triggers.

    RETURN QUERY SELECT v_email, v_password;
END;
$$;
GRANT EXECUTE ON FUNCTION public.user_create TO authenticated; -- Typically, only admins should create users.

-- Key Triggers on auth.user (conceptual, refer to migrations for exact implementation)

-- SECURITY INVOKER trigger to check role assignment permissions
CREATE OR REPLACE FUNCTION auth.check_role_permission() RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER AS $check_role_permission$
BEGIN
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.statbus_role IS DISTINCT FROM NEW.statbus_role) THEN
    IF NOT pg_has_role(current_user, NEW.statbus_role::text, 'MEMBER') THEN
      RAISE EXCEPTION 'Permission denied: Cannot assign role %.', NEW.statbus_role;
    END IF;
  END IF;
  RETURN NEW;
END;
$check_role_permission$;
CREATE TRIGGER check_role_permission_trigger BEFORE INSERT OR UPDATE ON auth.user
FOR EACH ROW EXECUTE FUNCTION auth.check_role_permission();

-- SECURITY DEFINER trigger to encrypt password and synchronize database role
CREATE OR REPLACE FUNCTION auth.sync_user_credentials_and_roles() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $sync_user_credentials_and_roles$
DECLARE
  role_name text := NEW.email;
  old_role_name text;
BEGIN
  -- Handle role rename on email change
  IF TG_OP = 'UPDATE' AND OLD.email IS DISTINCT FROM NEW.email THEN
    old_role_name := OLD.email;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = old_role_name) THEN
      EXECUTE format('ALTER ROLE %I RENAME TO %I', old_role_name, role_name);
    END IF;
  END IF;

  -- Create/ensure PostgreSQL role for the user (named after their email)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
    EXECUTE format('CREATE ROLE %I LOGIN INHERIT', role_name);
    EXECUTE format('GRANT authenticated TO %I', role_name);
    EXECUTE format('GRANT %I TO authenticator', role_name); -- Allow PostgREST to SET ROLE
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
  ELSIF TG_OP = 'UPDATE' AND OLD.statbus_role IS DISTINCT FROM NEW.statbus_role THEN
    IF OLD.statbus_role IS NOT NULL THEN
      EXECUTE format('REVOKE %I FROM %I', OLD.statbus_role::text, role_name);
    END IF;
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
  END IF;

  -- Encrypt password and set PostgreSQL role password
  IF NEW.password IS NOT NULL THEN
    NEW.encrypted_password := public.crypt(NEW.password, public.gen_salt('bf'));
    EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', role_name, NEW.password);
    NEW.password := NULL; -- Clear plain text password
  END IF;
  RETURN NEW;
END;
$sync_user_credentials_and_roles$;
CREATE TRIGGER sync_user_credentials_and_roles_trigger BEFORE INSERT OR UPDATE ON auth.user
FOR EACH ROW EXECUTE FUNCTION auth.sync_user_credentials_and_roles();

-- Trigger to drop the PostgreSQL role when a user is deleted
CREATE OR REPLACE FUNCTION auth.drop_user_role() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $drop_user_role$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = OLD.email) THEN
    EXECUTE format('DROP ROLE %I', OLD.email);
  END IF;
  RETURN OLD;
END;
$drop_user_role$;
CREATE TRIGGER drop_user_role_trigger AFTER DELETE ON auth.user
FOR EACH ROW EXECUTE FUNCTION auth.drop_user_role();
```
**Security Note**: The `auth.sync_user_credentials_and_roles` function is `SECURITY DEFINER`. Ensure it's owned by a superuser or a role with sufficient privileges to manage roles and passwords. The use of `format()` with `%I` (identifier) and `%L` (literal) is important for preventing SQL injection.

### 4. Login Function

The `public.login` function verifies credentials and returns an `auth.auth_response` object containing JWTs (access and refresh) and user details. It also sets HTTP-only cookies for the tokens. The JWT's `role` claim is set to the user's email.

```sql
-- Ensure pgjwt extension is installed: CREATE EXTENSION IF NOT EXISTS pgjwt;
-- Ensure app.settings.jwt_secret GUC is set:
-- ALTER DATABASE your_db_name SET "app.settings.jwt_secret" = 'your-very-secure-and-long-jwt-secret';

CREATE TYPE auth.auth_response AS (
  access_jwt text,
  refresh_jwt text,
  uid integer,
  sub uuid,
  email text,
  role text, -- This will be the user's email, for PostgREST's SET ROLE
  statbus_role public.statbus_role
);

-- Login function (simplified, see migrations for full version with session management)
CREATE OR REPLACE FUNCTION public.login(
    user_email TEXT,
    user_password TEXT
) RETURNS auth.auth_response
LANGUAGE plpgsql SECURITY DEFINER AS $login$
DECLARE
  _user auth.user;
  _response auth.auth_response;
  access_claims jsonb;
  refresh_claims jsonb;
  access_expires timestamptz := clock_timestamp() + interval '1 hour'; -- Example
  refresh_expires timestamptz := clock_timestamp() + interval '30 days'; -- Example
BEGIN
  SELECT u.* INTO _user FROM auth.user u
  WHERE u.email = login.user_email AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL;

  IF NOT FOUND OR _user.encrypted_password IS DISTINCT FROM public.crypt(user_password, _user.encrypted_password) THEN
    RETURN NULL; -- Invalid credentials
  END IF;

  -- Build JWT claims (see auth.build_jwt_claims in migrations)
  access_claims := auth.build_jwt_claims(p_email := _user.email, p_expires_at := access_expires, p_type := 'access');
  refresh_claims := auth.build_jwt_claims(p_email := _user.email, p_expires_at := refresh_expires, p_type := 'refresh',
    p_additional_claims := jsonb_build_object('jti', gen_random_uuid()::text) -- Example for refresh token session
  );

  _response.access_jwt := auth.generate_jwt(access_claims);
  _response.refresh_jwt := auth.generate_jwt(refresh_claims);
  _response.uid := _user.id;
  _response.sub := _user.sub;
  _response.email := _user.email;
  _response.role := _user.email; -- CRITICAL: PostgREST uses this for SET ROLE
  _response.statbus_role := _user.statbus_role;

  UPDATE auth.user SET last_sign_in_at = clock_timestamp() WHERE id = _user.id;

  -- Set cookies (see auth.set_auth_cookies in migrations)
  PERFORM auth.set_auth_cookies(_response.access_jwt, _response.refresh_jwt, access_expires, refresh_expires);

  RETURN _response;
END;
$login$;
GRANT EXECUTE ON FUNCTION public.login(TEXT, TEXT) TO anon;

-- Helper: auth.build_jwt_claims (conceptual, from migrations)
CREATE OR REPLACE FUNCTION auth.build_jwt_claims(
  p_email text, p_expires_at timestamptz, p_type text, p_additional_claims jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_user auth.user; v_claims jsonb;
BEGIN
  SELECT * INTO v_user FROM auth.user WHERE email = p_email;
  v_claims := jsonb_build_object(
    'role', v_user.email, 'statbus_role', v_user.statbus_role::text, 'sub', v_user.sub::text,
    'uid', v_user.id, 'email', v_user.email, 'type', p_type,
    'iat', extract(epoch from clock_timestamp())::integer,
    'exp', extract(epoch from p_expires_at)::integer
  );
  IF NOT p_additional_claims ? 'jti' THEN
    v_claims := v_claims || jsonb_build_object('jti', public.gen_random_uuid()::text);
  END IF;
  RETURN v_claims || p_additional_claims;
END; $$;
GRANT EXECUTE ON FUNCTION auth.build_jwt_claims TO authenticated; -- Or specific internal roles

-- Helper: auth.generate_jwt (conceptual, from migrations)
CREATE OR REPLACE FUNCTION auth.generate_jwt(claims jsonb) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN public.sign(claims::json, current_setting('app.settings.jwt_secret'));
END; $$;
GRANT EXECUTE ON FUNCTION auth.generate_jwt TO authenticated; -- Or specific internal roles

-- Helper: auth.set_auth_cookies (conceptual, from migrations)
CREATE OR REPLACE FUNCTION auth.set_auth_cookies(access_jwt text, refresh_jwt text, access_expires timestamptz, refresh_expires timestamptz)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE secure boolean := nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-proto' IS NOT DISTINCT FROM 'https';
    new_headers jsonb := coalesce(nullif(current_setting('response.headers', true), '')::jsonb, '[]'::jsonb);
BEGIN
  new_headers := new_headers || jsonb_build_array(jsonb_build_object('Set-Cookie',
    format('statbus=%s; Path=/; HttpOnly; SameSite=Strict; %sExpires=%s', access_jwt, CASE WHEN secure THEN 'Secure; ' ELSE '' END, to_char(access_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT')));
  new_headers := new_headers || jsonb_build_array(jsonb_build_object('Set-Cookie',
    format('statbus-refresh=%s; Path=/; HttpOnly; SameSite=Strict; %sExpires=%s', refresh_jwt, CASE WHEN secure THEN 'Secure; ' ELSE '' END, to_char(refresh_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT')));
  PERFORM set_config('response.headers', new_headers::text, true);
END; $$;
GRANT EXECUTE ON FUNCTION auth.set_auth_cookies TO authenticated; -- Or specific internal roles
```
**PostgreSQL GUC for `app.settings.jwt_secret`**:
Run `ALTER DATABASE your_database_name SET "app.settings.jwt_secret" = 'your-very-secure-and-long-jwt-secret';` once as a superuser.

### 5. Row Level Security (RLS)

With users operating under their email-named PostgreSQL roles, RLS policies use `current_user` (which evaluates to their email, e.g., `"user@example.com"`) and helper functions like `auth.uid()` or `auth.statbus_role()`.

```sql
-- Example: RLS on the auth.user table itself
ALTER TABLE auth.user ENABLE ROW LEVEL SECURITY;

-- Users can see and update their own record
CREATE POLICY select_own_user ON auth.user FOR SELECT USING (email = current_user);
CREATE POLICY update_own_user ON auth.user FOR UPDATE USING (email = current_user)
  WITH CHECK (email = current_user AND NOT (OLD.statbus_role IS DISTINCT FROM NEW.statbus_role AND NOT pg_has_role(current_user, NEW.statbus_role::text, 'MEMBER')));
  -- The WITH CHECK for update also prevents users from escalating their statbus_role unless they are already a member of the target role.

-- Admin users (members of 'admin_user' PostgreSQL role) have full access
CREATE POLICY admin_all_access ON auth.user FOR ALL
  USING (pg_has_role(current_user, 'admin_user', 'MEMBER'))
  WITH CHECK (pg_has_role(current_user, 'admin_user', 'MEMBER'));

GRANT SELECT, UPDATE (email, password, statbus_role /* other updatable fields */) ON auth.user TO authenticated;
GRANT INSERT, DELETE ON auth.user TO admin_user; -- Only admins can create/delete users directly through table

-- Example: RLS on auth.refresh_session (from migrations)
ALTER TABLE auth.refresh_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_refresh_sessions ON auth.refresh_session FOR SELECT USING (user_id = auth.uid());
CREATE POLICY insert_own_refresh_sessions ON auth.refresh_session FOR INSERT WITH CHECK (user_id = auth.uid());
-- ... and so on for update/delete. Admin policy also exists.
GRANT SELECT, UPDATE, DELETE, INSERT ON auth.refresh_session TO authenticated;
```
When a user (e.g., `user_abc@example.com`) makes an API request with their JWT, PostgREST will `SET ROLE "user_abc@example.com"`. Any query on `auth.user` (or other tables with similar RLS) will be filtered based on `current_user = '"user_abc@example.com"'` or `auth.uid()` which resolves to their ID.

## Workflow Summary

1.  **User Creation** (e.g., by an admin):
    *   Admin calls `public.user_create('new@example.com', 'regular_user', 'securepass')`.
    *   `auth.user` row is inserted.
    *   `auth.check_role_permission` trigger verifies admin can assign `regular_user`.
    *   `auth.sync_user_credentials_and_roles` trigger:
        *   Creates PostgreSQL role `"new@example.com"` with password `'securepass'`.
        *   Grants `"new@example.com"` to `authenticator`.
        *   Grants `authenticated` to `"new@example.com"`.
        *   Grants `regular_user` (the `statbus_role`) to `"new@example.com"`.
        *   Hashes `'securepass'` into `encrypted_password`, clears `password`.
2.  **User Login**:
    *   User sends credentials to PostgREST endpoint `/rpc/login` (`{"email": "new@example.com", "password": "securepass"}`).
    *   `public.login` verifies credentials against `auth.user.encrypted_password`.
    *   If valid, JWTs are generated. Access JWT includes `{"role": "new@example.com", "statbus_role": "regular_user", "sub": "...", "uid": ..., ...}`.
    *   Cookies `statbus` and `statbus-refresh` are set in the HTTP response.
    *   `auth.auth_response` object is returned.
3.  **API Request**:
    *   Client sends API request (e.g., `GET /user_data`) with `Authorization: Bearer <access_jwt>` or relies on the `statbus` cookie.
    *   PostgREST (connected as `authenticator`) verifies JWT, extracts `role` claim (`"new@example.com"`).
    *   PostgREST executes `SET ROLE "new@example.com";` for the current transaction.
    *   The database query is executed as PostgreSQL role `"new@example.com"`.
    *   RLS policies apply based on `current_user = '"new@example.com"'` and `auth.statbus_role() = 'regular_user'`.
4.  **Direct Database Access**:
    *   If `user@example.com` connects to PostgreSQL (their role `"user@example.com"` has `LOGIN` and a password), they operate as themselves. `current_user` is `"user@example.com"`. RLS applies identically.

## Benefits

-   **Unified Security Model**: Database is the single source of truth for permissions and RLS.
-   **Consistency**: Identical access control for API and direct database sessions.
-   **Granular Control**: Leverages PostgreSQL roles, `statbus_role` hierarchy, and RLS.
-   **Auditability**: Database logs show actions by specific user email roles.
-   **Leverages Database Features**: Robust PostgreSQL security mechanisms.
-   **Simplified User Role Management**: User's email directly maps to their PostgreSQL role name, managed by triggers.

## Considerations

-   **Role Naming**: User emails become PostgreSQL role names. Emails can contain special characters; PostgreSQL handles quoting for many, but complex emails might pose edge cases (though typically fine if quoted, e.g. `"user+alias@example.com"`). Max length of role names is 63 bytes.
-   **Role Management Complexity**: While triggers automate much, understanding the interaction between `public.user_create`, `auth.user` RLS, and the `auth.check_role_permission` and `auth.sync_user_credentials_and_roles` triggers is key. Deleting users requires handling the `auth.drop_user_role` trigger.
-   **`SECURITY DEFINER` Functions/Triggers**: `auth.sync_user_credentials_and_roles` and `auth.drop_user_role` are `SECURITY DEFINER`. They must be owned by a sufficiently privileged role (e.g., superuser or a dedicated role management role) and carefully audited for security.
-   **Password Management**: Passwords are set on PostgreSQL roles. If users connect directly to the DB, they use this password. The `public.change_password` and `public.admin_change_password` functions handle updating both `auth.user.encrypted_password` and the PostgreSQL role's password via the trigger.
-   **Transaction Management**: `CREATE ROLE` and `ALTER ROLE` (for password) are transaction-safe. The trigger system bundles these with `auth.user` modifications.
-   **Backup and Restore**: `pg_dumpall` correctly handles roles and their grants. `pg_dump` of a single database will include role membership if roles are global.

This approach provides a robust and consistent way to manage user authentication and authorization by deeply integrating application users with PostgreSQL's native security features, ensuring that API access and direct database access are governed by the same rules.
