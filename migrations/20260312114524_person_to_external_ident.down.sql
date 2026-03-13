BEGIN;

-- Reverse Migration E: Restore person.personal_ident, remove person_id from external_ident

-- Restore helper_process_external_idents to pre-Migration-E version
-- (references external_ident_type_enabled from Migration D, no person_id)
-- Note: full rollback of D would further change this back to _active

-- 1. Re-add personal_ident column to person
ALTER TABLE public.person ADD COLUMN personal_ident text UNIQUE;

-- 1b. Drop person edit-tracking columns (Fix 12 reverse)
DROP INDEX IF EXISTS ix_person_edit_by_user_id;
ALTER TABLE public.person DROP COLUMN IF EXISTS edit_at;
ALTER TABLE public.person DROP COLUMN IF EXISTS edit_by_user_id;
ALTER TABLE public.person DROP COLUMN IF EXISTS edit_comment;
ALTER TABLE public.person DROP COLUMN IF EXISTS death_date;

-- 2. Migrate data back from external_ident to person.personal_ident
UPDATE public.person AS p
SET personal_ident = ei.ident
FROM public.external_ident AS ei
JOIN public.external_ident_type AS eit ON ei.type_id = eit.id
WHERE eit.code = 'person_ident'
  AND ei.person_id = p.id;

-- 3. Delete person external_idents
DELETE FROM public.external_ident
WHERE person_id IS NOT NULL;

-- 4. Delete person_ident type
DELETE FROM public.external_ident_type WHERE code = 'person_ident';

-- 5. Drop person_id index
DROP INDEX IF EXISTS public.external_ident_person_id_idx;

-- 6. Restore original NULLS NOT DISTINCT index (without person_id)
DROP INDEX public.external_ident_type_unit_association_nulls_not_distinct;
CREATE UNIQUE INDEX external_ident_type_unit_association_nulls_not_distinct
    ON public.external_ident(type_id, establishment_id, legal_unit_id, enterprise_id, power_group_id)
    NULLS NOT DISTINCT;

-- 7. Restore original CHECK constraint (4 columns)
ALTER TABLE public.external_ident DROP CONSTRAINT "One and only one statistical unit id must be set";
ALTER TABLE public.external_ident ADD CONSTRAINT "One and only one statistical unit id must be set"
    CHECK (num_nonnulls(establishment_id, legal_unit_id, enterprise_id, power_group_id) = 1);

-- 8. Drop person_id column
ALTER TABLE public.external_ident DROP COLUMN person_id;

-- 9. Drop admin.person_id_exists
DROP FUNCTION IF EXISTS admin.person_id_exists(integer);

-- 10. Restore helper_process_external_idents to pre-Migration-E version (Fix 5)
-- This version references external_ident_type_enabled (from Migration D) and has no person_id.
-- When Migration D is also rolled back, it will change _enabled back to _active.
DO $do$
DECLARE
    v_funcdef TEXT;
    v_new_funcdef TEXT;
    v_func_oid OID;
BEGIN
    v_func_oid := 'import.helper_process_external_idents(integer,integer,text)'::regprocedure;
    v_funcdef := pg_get_functiondef(v_func_oid);

    -- Remove person_id = NULL from MERGE UPDATE SET clauses
    v_new_funcdef := replace(v_funcdef,
        E'                        person_id = NULL,\n                        edit_by_user_id = s.edit_by_user_id,',
        '                        edit_by_user_id = s.edit_by_user_id,'
    );

    IF v_new_funcdef IS DISTINCT FROM v_funcdef THEN
        v_new_funcdef := replace(v_new_funcdef, 'CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION');
        v_new_funcdef := replace(v_new_funcdef, 'CREATE PROCEDURE', 'CREATE OR REPLACE PROCEDURE');
        EXECUTE v_new_funcdef;
        RAISE NOTICE 'Restored helper_process_external_idents without person_id';
    ELSE
        RAISE WARNING 'helper_process_external_idents: expected person_id patterns not found';
    END IF;
END;
$do$;

END;
