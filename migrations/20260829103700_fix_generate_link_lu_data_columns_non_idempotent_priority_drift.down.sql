-- Down migration: restore import.generate_link_lu_data_columns to its
-- pre-STATBUS-314 form (dumped via \sf immediately before this migration
-- was authored -- the exact prior bytes, per house convention).
--
-- WARNING: this restores the NON-IDEMPOTENT, self-referential-MAX formula
-- that STATBUS-314 fixed -- see the up migration's header for the full
-- root-cause writeup and the architect's formula-authority ruling. This is
-- DELIBERATE: a down migration's job is to restore PRIOR CODE BEHAVIOR,
-- and the prior behavior here genuinely was the buggy formula -- do not
-- "fix" this down migration to ship the corrected formula instead, that
-- would defeat the point of being able to roll back to what actually ran
-- before.
--
-- It does NOT attempt to un-converge the priorities the up migration's
-- CALL already wrote, and must never be made to: those converged values
-- are correct data, not an artifact of the bug, and a rollback that
-- reverted correct data to chase code-symmetry would be strictly worse
-- than one that leaves it alone (same principle as STATBUS-309's
-- deleted_at and STATBUS-312's own direction -- data a fix legitimately
-- produced is never something a down migration's job is to erase). Rows
-- simply keep whatever value the fix converged them to; the next
-- external_ident_type mutation resumes drifting from there under the
-- restored buggy formula. Same posture as every other down migration in
-- this codebase that restores prior logic without trying to undo data an
-- up migration's CALL/UPDATE already committed (e.g.
-- 20260828225222_repair_tag_object_sha_pollution_rc14_rc15.down.sql).

BEGIN;

CREATE OR REPLACE PROCEDURE import.generate_link_lu_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_def RECORD;
    v_current_priority INT;
    v_active_codes TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'link_establishment_to_legal_unit';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'link_establishment_to_legal_unit step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_enabled;
    RAISE DEBUG '[import.generate_link_lu_data_columns] For step_id % (link_establishment_to_legal_unit), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    SELECT COALESCE(MAX(idc.priority), 0) INTO v_current_priority
    FROM public.import_data_column idc WHERE idc.step_id = v_step_id;

    -- Add source_input column for each active external_ident_type, prefixed with 'legal_unit_'
    FOR v_ident_type IN SELECT code FROM public.external_ident_type_enabled ORDER BY priority
    LOOP
        v_current_priority := v_current_priority + 1;
        INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
        VALUES (v_step_id, 'legal_unit_' || v_ident_type.code || '_raw', 'TEXT', 'source_input', true, false, v_current_priority, 'TEXT')
        ON CONFLICT (step_id, column_name) DO UPDATE SET
            priority = EXCLUDED.priority,
            is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
            target_pg_type = EXCLUDED.target_pg_type;
    END LOOP;

    -- The 'legal_unit_id' pk_id column is statically defined in 20250505120000_import_populate_steps.up.sql
    -- and should not be managed by this dynamic lifecycle callback.
END;
$procedure$;

COMMIT;
