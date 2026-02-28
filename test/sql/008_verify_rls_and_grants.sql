-- This test verifies that all public tables have RLS enabled and all public
-- views have proper grants. It also generates security documentation at
-- doc/db/security.md.
--
-- When a developer adds a new table without RLS, this test fails and the
-- diff shows exactly which table is missing and the fix command to add
-- to their migration.
--
-- Additional checks:
--   A. SECURITY DEFINER function registry — any unlisted function fails
--   B. View security_invoker check — missing security_invoker on non-exempt views
--   C. Duplicate policy detection — same (command, role) on one table
--   D. search_path check on SECURITY DEFINER — missing SET search_path

-- Turn off decorative output for clean markdown generation
\t
\a

-- Create the docs directory if it doesn't exist
\! mkdir -p doc/db

CREATE OR REPLACE FUNCTION public.generate_security_doc(
    OUT doc TEXT,
    OUT verification TEXT
)
LANGUAGE plpgsql AS $generate_security_doc$
DECLARE
    v_doc TEXT := '';
    v_problems TEXT[] := ARRAY[]::text[];
    v_rec RECORD;
    v_policy_str TEXT;
    v_grant_str TEXT;
    v_role_name TEXT;
    v_privilege_name TEXT;
    v_required_roles TEXT[] := ARRAY['authenticated', 'regular_user', 'admin_user'];
    v_required_privileges TEXT[];  -- Set per-view based on insertability
    -- Tables that are intentionally exempt from RLS because they are internal
    -- staging/working tables not exposed via PostgREST.
    v_exempt_tables TEXT[] := ARRAY[
        'statistical_history_facet_partitions',
        'statistical_unit_facet_dirty_partitions',
        'statistical_unit_facet_staging',
        'statistical_unit_staging'
    ];
    -- Views with intentionally non-standard grant patterns.
    -- public.user: security_barrier view, user creation via user_create() function,
    --   only authenticated has SELECT, specific column UPDATE grants.
    v_exempt_views TEXT[] := ARRAY[
        'user'
    ];

    -- === SECURITY DEFINER Registry ===
    -- Every SECURITY DEFINER function must be listed here with justification.
    -- Unlisted functions cause a test failure.

    -- Authentication & Sessions: Access auth.secrets (force-RLS, zero policies),
    -- auth.user (RLS), session management
    v_auth_session_funcs TEXT[] := ARRAY[
        'auth.auto_create_api_token_on_confirmation',
        'auth.check_api_key_revocation',
        'auth.cleanup_expired_sessions',
        'auth.drop_user_role',
        'auth.generate_api_key_token',
        'auth.jwt_verify',
        'auth.sync_user_credentials_and_roles',
        'public.auth_expire_access_keep_refresh',
        'public.auth_status',
        'public.list_active_sessions',
        'public.login',
        'public.logout',
        'public.refresh',
        'public.revoke_session'
    ];

    -- Import System: DDL (CREATE/DROP TABLE), session context manipulation
    v_import_funcs TEXT[] := ARRAY[
        'admin.import_job_cleanup',
        'admin.import_job_generate',
        'admin.reset_import_job_user_context',
        'admin.set_import_job_user_context',
        'admin.set_optimal_import_session_settings',
        'import.process_power_group_link',
        'public.get_import_job_progress'
    ];

    -- Worker/Derive Pipeline: Write to RLS-protected tables, DDL, worker orchestration
    v_worker_funcs TEXT[] := ARRAY[
        'admin.disable_temporal_triggers',
        'admin.enable_temporal_triggers',
        'worker.command_collect_changes',
        'worker.command_import_job_cleanup',
        'worker.command_task_cleanup',
        'worker.derive_power_groups',
        'worker.derive_reports',
        'worker.derive_statistical_history',
        'worker.derive_statistical_history_facet',
        'worker.derive_statistical_history_facet_period',
        'worker.derive_statistical_history_period',
        'worker.derive_statistical_unit',
        'worker.derive_statistical_unit_continue',
        'worker.derive_statistical_unit_facet',
        'worker.derive_statistical_unit_facet_partition',
        'worker.statistical_history_facet_reduce',
        'worker.statistical_history_reduce',
        'worker.statistical_unit_facet_reduce',
        'worker.statistical_unit_flush_staging',
        'worker.statistical_unit_refresh_batch'
    ];

    -- Settings/Partition Management: Write to RLS-protected tables on settings change
    v_settings_funcs TEXT[] := ARRAY[
        'admin.adjust_analytics_partition_count',
        'admin.propagate_partition_count_change'
    ];

    -- Derived Table Refresh: Bulk DELETE+INSERT on RLS-protected tables
    v_derive_funcs TEXT[] := ARRAY[
        'public.activity_category_used_derive',
        'public.data_source_used_derive',
        'public.region_used_derive',
        'public.sector_used_derive'
    ];

    -- Drilldown Functions: Performance — avoid RLS evaluation on large read-only queries
    v_drilldown_funcs TEXT[] := ARRAY[
        'public.statistical_history_drilldown',
        'public.statistical_unit_facet_drilldown'
    ];

    -- GraphQL Schema: Access graphql schema sequence (no grants to non-postgres)
    v_graphql_funcs TEXT[] := ARRAY[
        'graphql.get_schema_version',
        'graphql.increment_schema_version'
    ];

    -- Lifecycle Callbacks: Trigger functions calling DDL procedures or enqueuing worker tasks
    v_lifecycle_funcs TEXT[] := ARRAY[
        'lifecycle_callbacks.cleanup_and_generate',
        'public.generate_power_ident',
        'public.legal_relationship_cycle_check',
        'public.legal_relationship_queue_derive_power_groups'
    ];

    -- Combined registry (excluding sql_saga which is matched by schema)
    v_all_registered_funcs TEXT[];

    -- Views exempt from security_invoker requirement
    -- Extension views, sql_saga internal views, public.user (security_barrier)
    v_invoker_exempt_views TEXT[] := ARRAY[
        'hypopg_hidden_indexes',
        'hypopg_list_indexes',
        'pg_stat_monitor',
        'pg_stat_statements',
        'pg_stat_statements_info',
        'user'
    ];
BEGIN
    -- Build combined registry
    v_all_registered_funcs :=
        v_auth_session_funcs ||
        v_import_funcs ||
        v_worker_funcs ||
        v_settings_funcs ||
        v_derive_funcs ||
        v_drilldown_funcs ||
        v_graphql_funcs ||
        v_lifecycle_funcs;

    -- ========== Generate Documentation ==========

    v_doc := '# StatBus Security Posture

This document is automatically generated by `test/sql/008_verify_rls_and_grants.sql`. Do not edit it manually.

## Database Roles

| Role | Purpose |
|------|---------|
| `postgres` | Superuser, owns all objects |
| `authenticator` | PostgREST connects as this role, then switches via JWT |
| `anon` | Unauthenticated requests (very limited access) |
| `authenticated` | Base role for all logged-in users (SELECT on most tables) |
| `regular_user` | Standard user — can read most tables, edit core business data |
| `restricted_user` | User with region/activity restrictions applied via RLS |
| `admin_user` | Full access to all tables |
| `super_user` | Administrative operations |
| `notify_reader` | Can read notifications (used by worker) |

## Row Level Security (RLS)

All public tables must have RLS enabled. RLS policies control which rows
each role can see and modify.
';

    -- === Public Tables with RLS ===
    v_doc := v_doc || E'\n### Public Tables\n\n';

    FOR v_rec IN
        SELECT c.relname AS table_name,
               c.relrowsecurity AS has_rls
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'
        ORDER BY c.relname
    LOOP
        IF v_rec.has_rls THEN
            -- Get policies for this table
            SELECT string_agg(
                format('`%s` (%s → %s)',
                    pol.polname,
                    CASE pol.polcmd
                        WHEN 'r' THEN 'SELECT'
                        WHEN 'a' THEN 'INSERT'
                        WHEN 'w' THEN 'UPDATE'
                        WHEN 'd' THEN 'DELETE'
                        WHEN '*' THEN 'ALL'
                    END,
                    COALESCE(
                        NULLIF(array_to_string(
                            ARRAY(SELECT rolname FROM pg_roles WHERE oid = ANY(pol.polroles) ORDER BY rolname),
                            ', '
                        ), ''),
                        'PUBLIC'
                    )
                ),
                ', ' ORDER BY pol.polname
            )
            INTO v_policy_str
            FROM pg_policy pol
            JOIN pg_class pc ON pol.polrelid = pc.oid
            JOIN pg_namespace pn ON pc.relnamespace = pn.oid
            WHERE pn.nspname = 'public'
              AND pc.relname = v_rec.table_name;

            v_doc := v_doc || format(E'- **`%s`** — RLS ON\n', v_rec.table_name);
            IF v_policy_str IS NOT NULL THEN
                v_doc := v_doc || format(E'  - Policies: %s\n', v_policy_str);
            END IF;
        ELSE
            IF v_rec.table_name = ANY(v_exempt_tables) THEN
                v_doc := v_doc || format(E'- **`%s`** — RLS OFF (exempt: internal staging table)\n', v_rec.table_name);
            ELSE
                v_doc := v_doc || format(E'- **`%s`** — **RLS OFF** ⚠️\n', v_rec.table_name);
            END IF;
        END IF;
    END LOOP;

    -- === Non-public schema tables with RLS ===
    v_doc := v_doc || E'\n### Non-Public Schema Tables with RLS\n\n';

    FOR v_rec IN
        SELECT n.nspname AS schema_name,
               c.relname AS table_name,
               c.relrowsecurity AS has_rls
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname IN ('auth', 'db', 'worker', 'import', 'lifecycle_callbacks')
          AND c.relkind = 'r'
          AND c.relrowsecurity
        ORDER BY n.nspname, c.relname
    LOOP
        SELECT string_agg(
            format('`%s` (%s → %s)',
                pol.polname,
                CASE pol.polcmd
                    WHEN 'r' THEN 'SELECT'
                    WHEN 'a' THEN 'INSERT'
                    WHEN 'w' THEN 'UPDATE'
                    WHEN 'd' THEN 'DELETE'
                    WHEN '*' THEN 'ALL'
                END,
                COALESCE(
                    NULLIF(array_to_string(
                        ARRAY(SELECT rolname FROM pg_roles WHERE oid = ANY(pol.polroles) ORDER BY rolname),
                        ', '
                    ), ''),
                    'PUBLIC'
                )
            ),
            ', ' ORDER BY pol.polname
        )
        INTO v_policy_str
        FROM pg_policy pol
        JOIN pg_class pc ON pol.polrelid = pc.oid
        JOIN pg_namespace pn ON pc.relnamespace = pn.oid
        WHERE pn.nspname = v_rec.schema_name
          AND pc.relname = v_rec.table_name;

        v_doc := v_doc || format(E'- **`%s.%s`** — RLS ON\n', v_rec.schema_name, v_rec.table_name);
        IF v_policy_str IS NOT NULL THEN
            v_doc := v_doc || format(E'  - Policies: %s\n', v_policy_str);
        END IF;
    END LOOP;

    -- === View Grants ===
    v_doc := v_doc || E'\n## View Grants\n\nPublic views (excluding `*__for_portion_of_valid`) must have SELECT granted to\n`authenticated`, `regular_user`, and `admin_user`. Insertable views (simple\nauto-updatable) also require INSERT.\n\n';

    FOR v_rec IN
        SELECT c.relname AS view_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relkind = 'v'
          AND c.relname NOT LIKE '%__for_portion_of_valid'
        ORDER BY c.relname
    LOOP
        -- Build grant summary for this view
        SELECT string_agg(
            format('%s: %s', r.rolname, privs.privlist),
            '; ' ORDER BY r.rolname
        )
        INTO v_grant_str
        FROM (VALUES ('authenticated'), ('regular_user'), ('admin_user')) AS roles(rolname)
        JOIN pg_roles r ON r.rolname = roles.rolname
        CROSS JOIN LATERAL (
            SELECT string_agg(priv, ', ' ORDER BY priv) AS privlist
            FROM (
                SELECT 'SELECT' AS priv
                WHERE has_table_privilege(r.oid, format('public.%I', v_rec.view_name)::regclass, 'SELECT')
                UNION ALL
                SELECT 'INSERT'
                WHERE has_table_privilege(r.oid, format('public.%I', v_rec.view_name)::regclass, 'INSERT')
                UNION ALL
                SELECT 'UPDATE'
                WHERE has_table_privilege(r.oid, format('public.%I', v_rec.view_name)::regclass, 'UPDATE')
                UNION ALL
                SELECT 'DELETE'
                WHERE has_table_privilege(r.oid, format('public.%I', v_rec.view_name)::regclass, 'DELETE')
            ) sub
        ) privs
        WHERE privs.privlist IS NOT NULL;

        v_doc := v_doc || format(E'- **`%s`**', v_rec.view_name);
        IF v_grant_str IS NOT NULL THEN
            v_doc := v_doc || format(E': %s', v_grant_str);
        ELSE
            v_doc := v_doc || E': **NO GRANTS** ⚠️';
        END IF;
        v_doc := v_doc || E'\n';
    END LOOP;

    -- === SECURITY DEFINER Functions ===
    v_doc := v_doc || E'\n## SECURITY DEFINER Functions\n\nFunctions that bypass RLS by executing as the function owner. Each must be\nregistered in the test with justification.\n\n';

    v_doc := v_doc || E'### Authentication & Sessions\n\nAccess `auth.secrets` (force-RLS, zero policies), `auth.user` (RLS), session management.\n\n';
    FOR v_rec IN
        SELECT unnest(v_auth_session_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### Import System\n\nDDL (CREATE/DROP TABLE), session context manipulation.\n\n';
    FOR v_rec IN
        SELECT unnest(v_import_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### Worker/Derive Pipeline\n\nWrite to RLS-protected tables, DDL, worker orchestration.\n\n';
    FOR v_rec IN
        SELECT unnest(v_worker_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### Settings/Partition Management\n\nWrite to RLS-protected tables on settings change.\n\n';
    FOR v_rec IN
        SELECT unnest(v_settings_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### Derived Table Refresh\n\nBulk DELETE+INSERT on RLS-protected tables.\n\n';
    FOR v_rec IN
        SELECT unnest(v_derive_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### Drilldown Functions\n\nPerformance: avoid RLS evaluation on large read-only queries.\n\n';
    FOR v_rec IN
        SELECT unnest(v_drilldown_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### GraphQL Schema\n\nAccess `graphql` schema sequence (no grants to non-postgres).\n\n';
    FOR v_rec IN
        SELECT unnest(v_graphql_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### Lifecycle Callbacks\n\nTrigger calling DDL procedures.\n\n';
    FOR v_rec IN
        SELECT unnest(v_lifecycle_funcs) AS func_name ORDER BY 1
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    v_doc := v_doc || E'\n### sql_saga\n\nDDL operations (CREATE/ALTER/DROP on tables, views, triggers). Matched by schema.\n\n';
    FOR v_rec IN
        SELECT format('%s.%s', n.nspname, p.proname) AS func_name
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.prosecdef = true AND n.nspname = 'sql_saga'
        ORDER BY p.proname
    LOOP
        v_doc := v_doc || format(E'- `%s`\n', v_rec.func_name);
    END LOOP;

    -- ========== Verification ==========

    -- Check 1: Public tables without RLS (excluding exempt tables)
    FOR v_rec IN
        SELECT c.relname AS table_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'
          AND NOT c.relrowsecurity
          AND c.relname <> ALL(v_exempt_tables)
        ORDER BY c.relname
    LOOP
        -- Suggest edit if table looks like a core business table, read otherwise
        IF v_rec.table_name IN ('establishment', 'legal_unit', 'enterprise',
                                'power_group', 'legal_relationship', 'activity', 'contact',
                                'location', 'person', 'person_for_unit',
                                'stat_for_unit', 'image', 'external_ident',
                                'tag_for_unit', 'unit_notes') THEN
            v_problems := array_append(v_problems,
                format('MISSING RLS: public.%s — fix with: SELECT admin.add_rls_regular_user_can_edit(''public.%s'');',
                    v_rec.table_name, v_rec.table_name));
        ELSE
            v_problems := array_append(v_problems,
                format('MISSING RLS: public.%s — fix with: SELECT admin.add_rls_regular_user_can_read(''public.%s'');',
                    v_rec.table_name, v_rec.table_name));
        END IF;
    END LOOP;

    -- Check 2: Public views without proper grants (excluding exempt views)
    -- All views need SELECT; only insertable views also need INSERT.
    FOR v_rec IN
        SELECT c.relname AS view_name,
               iv.is_insertable_into = 'YES' AS is_insertable
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        LEFT JOIN information_schema.views iv
          ON iv.table_schema = 'public' AND iv.table_name = c.relname
        WHERE n.nspname = 'public'
          AND c.relkind = 'v'
          AND c.relname NOT LIKE '%__for_portion_of_valid'
          AND c.relname <> ALL(v_exempt_views)
        ORDER BY c.relname
    LOOP
        IF v_rec.is_insertable THEN
            v_required_privileges := ARRAY['SELECT', 'INSERT'];
        ELSE
            v_required_privileges := ARRAY['SELECT'];
        END IF;

        FOREACH v_role_name IN ARRAY v_required_roles
        LOOP
            FOREACH v_privilege_name IN ARRAY v_required_privileges
            LOOP
                IF NOT has_table_privilege(
                    v_role_name,
                    format('public.%I', v_rec.view_name)::regclass,
                    v_privilege_name
                ) THEN
                    v_problems := array_append(v_problems,
                        format('MISSING GRANT: %s on public.%s for %s — fix with: GRANT %s ON public.%s TO %s;',
                            v_privilege_name, v_rec.view_name, v_role_name,
                            v_privilege_name, v_rec.view_name, v_role_name));
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;

    -- Check 3 (A): Unlisted SECURITY DEFINER functions
    FOR v_rec IN
        SELECT format('%s.%s', n.nspname, p.proname) AS func_name
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.prosecdef = true
          AND n.nspname <> 'sql_saga'  -- sql_saga matched by schema
          AND format('%s.%s', n.nspname, p.proname) <> ALL(v_all_registered_funcs)
        ORDER BY n.nspname, p.proname
    LOOP
        v_problems := array_append(v_problems,
            format('UNLISTED SECURITY DEFINER: %s — add to registry in test/sql/008_verify_rls_and_grants.sql',
                v_rec.func_name));
    END LOOP;

    -- Check 4 (B): Views missing security_invoker (excluding exempt views and __for_portion_of_valid)
    FOR v_rec IN
        SELECT c.relname AS view_name
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relkind = 'v'
          AND c.relname NOT LIKE '%__for_portion_of_valid'
          AND c.relname <> ALL(v_invoker_exempt_views)
          AND NOT COALESCE(
              (SELECT option_value::boolean
               FROM pg_options_to_table(c.reloptions)
               WHERE option_name = 'security_invoker'),
              false)
        ORDER BY c.relname
    LOOP
        v_problems := array_append(v_problems,
            format('MISSING SECURITY_INVOKER: public.%s — fix with: ALTER VIEW public.%s SET (security_invoker = on);',
                v_rec.view_name, v_rec.view_name));
    END LOOP;

    -- Check 5 (C): Duplicate policies (same table, command, role)
    FOR v_rec IN
        SELECT p.schemaname, p.tablename, p.cmd,
               r.rolname AS role_name,
               count(*) AS policy_count,
               string_agg(p.policyname, ', ' ORDER BY p.policyname) AS policy_names
        FROM pg_policies p
        CROSS JOIN LATERAL unnest(p.roles::text[]) AS r(rolname)
        WHERE p.schemaname = 'public'
        GROUP BY p.schemaname, p.tablename, p.cmd, r.rolname
        HAVING count(*) > 1
        ORDER BY p.tablename, p.cmd, r.rolname
    LOOP
        v_problems := array_append(v_problems,
            format('DUPLICATE POLICY: public.%s has %s policies for %s/%s: %s',
                v_rec.tablename, v_rec.policy_count, v_rec.cmd, v_rec.role_name, v_rec.policy_names));
    END LOOP;

    -- Check 6 (D): SECURITY DEFINER functions without SET search_path (excluding sql_saga)
    FOR v_rec IN
        SELECT format('%s.%s', n.nspname, p.proname) AS func_name
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.prosecdef = true
          AND n.nspname <> 'sql_saga'
          AND NOT EXISTS (
              SELECT 1
              FROM unnest(p.proconfig) AS cfg
              WHERE cfg LIKE 'search_path=%'
          )
        ORDER BY n.nspname, p.proname
    LOOP
        v_problems := array_append(v_problems,
            format('MISSING SEARCH_PATH: %s — SECURITY DEFINER without SET search_path is a privilege escalation risk',
                v_rec.func_name));
    END LOOP;

    -- Build verification output
    IF array_length(v_problems, 1) > 0 THEN
        verification := array_to_string(v_problems, E'\n');
    ELSE
        verification := 'OK: All tables have RLS and all views have grants';
    END IF;

    doc := v_doc;
END;
$generate_security_doc$;

-- Generate the documentation and capture the output
SELECT * FROM public.generate_security_doc() \gset

-- Write the doc file
\o doc/db/security.md
SELECT :'doc';
\o

-- Clean up the function
DROP FUNCTION public.generate_security_doc();

-- Turn decorative output back on for the test result
\t
\a

-- Confirm doc generation
SELECT 'Security documentation generated in doc/db/security.md' AS result;

-- Output the verification result (this is what the test compares)
SELECT :'verification';
