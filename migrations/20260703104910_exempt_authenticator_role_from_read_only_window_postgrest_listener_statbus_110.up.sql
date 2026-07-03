-- Migration 20260703104910: exempt authenticator role from read only window postgrest listener statbus_110
BEGIN;

-- STATBUS-110 read-only-window regression fix (doc-023). The window
-- (ALTER DATABASE ... SET default_transaction_read_only = on) makes PostgREST's
-- pgrst-channel LISTENER fail at connect: it opens with target_session_attrs=
-- read-write, so libpq runs SHOW transaction_read_only and rejects the session
-- ("session is read-only") → /ready 503 → the post-upgrade health check never
-- passes → the upgrade wedges/rolls back.
--
-- Exempt the authenticator role: PostgreSQL role-GUC OUTRANKS database-GUC, so an
-- authenticator session reports writable even while the database default is on.
-- The listener connects, /ready goes green, the health check passes — WHILE the
-- database read-only default still freezes every other role (worker, app,
-- direct-PG integrators). This opens NO external write path: PostgREST's external
-- /rest writes are maintenance-503-gated (Caddy @maintenance) throughout the
-- window; 110's unique contribution was the direct-PG (Layer4) path, which uses
-- OTHER roles, not authenticator. A no-op outside the window (the database default
-- is off normally). Applies within the same upgrade that ships it: migrate (step
-- 10) runs before REST restarts (step 11).
ALTER ROLE authenticator SET default_transaction_read_only = off;

END;
