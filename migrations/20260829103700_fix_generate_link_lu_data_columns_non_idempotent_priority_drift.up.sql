-- Migration 20260829103700: fix non-idempotent priority drift in
-- import.generate_link_lu_data_columns (STATBUS-314/108 family, second
-- instance of the seed-path-divergence disease STATBUS-312 first found).
--
-- ROOT CAUSE (verified empirically, non-destructively, via BEGIN/CALL/CALL/
-- ROLLBACK on a live database): the procedure computed its base priority as
--
--   SELECT COALESCE(MAX(idc.priority), 0) INTO v_current_priority
--   FROM public.import_data_column idc WHERE idc.step_id = v_step_id;
--
-- -- MAX over ALL rows in the step, with NO purpose filter, so the base
-- includes the procedure's OWN previously-inserted 'source_input' rows.
-- Every subsequent call re-bases off its own last output and climbs by
-- (count of active external_ident_type rows). This procedure fires via
-- the external_ident_type_lifecycle_callbacks_after_{insert,update,delete}
-- triggers -> lifecycle_callbacks.cleanup_and_generate(), STATEMENT-level,
-- on every INSERT/UPDATE/DELETE against public.external_ident_type -- so
-- every unrelated edit to that table (renaming a type, reordering
-- priorities, enabling/disabling one) silently pushes these columns'
-- priorities upward, independently on every database that has ever made
-- such an edit. Confirmed: 2 active types, 2 extra calls, priorities
-- climbed +2 then +2 again -- exactly the STATBUS-108 diff shape (3 active
-- types, blessed shows 8/9/10, a full-replay-derived database showed
-- 14/15/16 -- a +6 gap, i.e. 2 extra firings' worth for 3 types).
--
-- THERE IS NO SINGLE "FLEET VALUE" TO RESTORE: every real box has
-- independently drifted by its own, unrecoverable amount depending on how
-- many times its own external_ident_type table was ever touched -- there
-- is no historical value worth reconstructing. Architect's formula-
-- authority ruling for this class of defect (STATBUS-314): "the fleet is
-- authoritative when coherent; where a defect made it incoherent, the
-- definition is authoritative and every box converges to it." The fix is
-- the invariant, not a target number: for a given set of active ident
-- types, output must be identical regardless of how many times this
-- procedure has run and regardless of current table contents.
--
-- FORMULA SHAPE (architect review, amending the first draft): the sibling
-- import.generate_external_ident_data_columns is idempotent only BY
-- FILTER -- a MAX carefully excluding its own output purpose, one
-- purpose-value away from re-basing on itself if that exclusion list ever
-- goes stale. import.generate_stat_var_data_columns is idempotent BY
-- CONSTRUCTION -- a pure function of the driving row's own static
-- priority, no MAX over anything, filtered or otherwise. This fix follows
-- the stat_var pattern, not the external_idents one: v_static_base is a
-- targeted lookup of the ONE known-static row this procedure has never
-- written and never will (primary_for_legal_unit, purpose='internal',
-- fixed forever at priority 1 by 20250505120000_import_populate_steps.up.sql's
-- own PARTITION BY step_code row-numbering over an immutable, already-
-- released VALUES list) -- not an aggregate over "whatever this step
-- currently contains" in any form. Priority becomes
-- v_static_base + v_ident_type.priority: deterministic, ordered by the
-- ident type's own priority, and structurally incapable of referencing
-- this procedure's own prior output, because the looked-up row is never
-- one this procedure inserts.
--
-- CONVERGENCE, NOT RECONSTRUCTION: the CALL at the end of this migration
-- runs the corrected, now-idempotent procedure once on every database that
-- applies it -- fleet box or fresh full replay alike -- so every one lands
-- on the SAME corrected value from here on, regardless of how far each had
-- independently drifted before. Purely a priority (ordering/display)
-- correction: import jobs match data columns by column_name, never by
-- priority, so this changes no import behavior, only the columns' declared
-- order.
--
-- Idempotent by construction: re-running this migration re-applies the
-- same CREATE OR REPLACE and CALLs the now-idempotent procedure again,
-- which is a genuine no-op on a database already at the corrected value.

BEGIN;

CREATE OR REPLACE PROCEDURE import.generate_link_lu_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_static_base INT;
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'link_establishment_to_legal_unit step not found, cannot generate data columns.';
        RETURN;
    END IF;

    -- STATBUS-314: a TARGETED lookup of the one known-static row this
    -- procedure has never written and never will -- NOT a MAX/aggregate
    -- over the step's contents, filtered or otherwise (that shape is only
    -- idempotent-by-filter, one purpose-value away from re-basing on its
    -- own output again). primary_for_legal_unit's priority is fixed
    -- forever by 20250505120000_import_populate_steps.up.sql's
    -- PARTITION BY step_code row-numbering over an immutable, already-
    -- released VALUES list, so this lookup can never drift and can never
    -- match a row this procedure itself inserts.
    SELECT idc.priority INTO STRICT v_static_base
    FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.column_name = 'primary_for_legal_unit';

    -- Priority is now a pure function of the static base and the ident
    -- type's own priority -- never of what this procedure has previously
    -- written -- matching the already-idempotent sibling
    -- (import.generate_stat_var_data_columns).
    FOR v_ident_type IN SELECT code, priority FROM public.external_ident_type_enabled ORDER BY priority
    LOOP
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code || '_raw', 'TEXT', 'source_input', true, false, v_static_base + v_ident_type.priority, 'TEXT')
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type;
    END LOOP;

    -- The 'legal_unit_id' pk_id column is statically defined in 20250505120000_import_populate_steps.up.sql
    -- and should not be managed by this dynamic lifecycle callback.
END;
$procedure$;

-- Converge every database that applies this migration -- fleet box or
-- fresh full replay alike -- to the corrected value right now. The
-- CREATE OR REPLACE above only prevents FUTURE drift; existing rows still
-- hold whatever each database's own history of external_ident_type churn
-- happened to produce until this runs.
CALL import.generate_link_lu_data_columns();

COMMIT;
