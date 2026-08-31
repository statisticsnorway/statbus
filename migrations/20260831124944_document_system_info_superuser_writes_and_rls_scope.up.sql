-- Migration 20260831124944: document system_info superuser writes and rls scope
BEGIN;

-- STATBUS-308/STATBUS-326. Architect's ruling (2026-08-31): the RLS policies on
-- this table describe what a USER may do, not the complete set of writers — the
-- upgrade service AND the install verb (cli/cmd/install.go:2553
-- stampInstallInvocationTracking, via connectInstallDB -> migrate.AdminConnStr,
-- same POSTGRES_ADMIN_USER DSN as cli/internal/upgrade/service.go's
-- recoveryDSN/connect) both write their own keys over a SUPERUSER connection,
-- bypassing RLS entirely. A policy-layer audit of this table must not read
-- 'admin_user manage' as the whole writer set. doc/db now renders table
-- comments (STATBUS-326), so this note lands beside the Policies block an
-- auditor actually reads.
COMMENT ON TABLE public.system_info IS
'Key/value system state surfaced to the admin UI.

RLS ON THIS TABLE GOVERNS USERS, NOT WRITERS. The policies here (authenticated
SELECT, admin_user manage) describe what a USER may do. They are NOT the complete
list of who writes: the upgrade service and the install verb write their own keys
over a SUPERUSER connection, which bypasses RLS entirely.

So a policy-layer audit of this table must not conclude that admin_user is the whole
writer set. It is not, and the catalog cannot show you the rest.

The bypass is the accepted contract, not an oversight: these writers are system
components reporting state, not users acting on data — and a policy written for a
superuser role would be inert, sitting in pg_policy looking like a constraint while
constraining nothing. Governing them by policy would require giving the service a
least-privilege role instead of superuser (STATBUS-308).';

END;
