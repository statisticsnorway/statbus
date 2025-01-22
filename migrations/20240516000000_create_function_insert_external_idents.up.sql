BEGIN;

CREATE OR REPLACE FUNCTION admin.insert_external_idents(
    new_jsonb JSONB,
    external_idents_to_add public.external_ident[],
    p_legal_unit_id INTEGER,
    p_establishment_id INTEGER,
    p_updated_by_user_id INTEGER
) RETURNS void LANGUAGE plpgsql AS $insert_external_idents$
DECLARE
  unit_type TEXT;
BEGIN
  -- Ensure that either legal_unit_id or establishment_id is provided, but not both.
  IF (p_legal_unit_id IS NOT NULL AND p_establishment_id IS NOT NULL) OR
      (p_legal_unit_id IS NULL AND p_establishment_id IS NULL) THEN
      RAISE EXCEPTION 'Must provide either a p_legal_unit_id or an p_establishment_id, but not both.';
  ELSIF p_legal_unit_id IS NOT NULL THEN
    unit_type := 'legal_unit';
  ELSIF p_establishment_id IS NOT NULL THEN
    unit_type := 'establishment';
  END IF;

  IF array_length(external_idents_to_add, 1) > 0 THEN
    BEGIN
      INSERT INTO public.external_ident
          ( type_id
          , ident
          , legal_unit_id
          , establishment_id
          , updated_by_user_id
          )
      SELECT type_id
            , ident
            , p_legal_unit_id
            , p_establishment_id
            , p_updated_by_user_id
      FROM unnest(external_idents_to_add);
    EXCEPTION WHEN unique_violation THEN
      DECLARE
        identifier_problems_jsonb JSONB;
      BEGIN
        RAISE DEBUG 'External identifiers to add: %', to_jsonb(external_idents_to_add);
        -- There are two scenarios to consider.
        -- 1. Conflicting Ident: If there is an existing identifier conflict on (type,ident) for another entry
        -- 2. Unstable Ident: If there is an existing identifier conflict on (type, legal_unit_id) or (type, establishment_id) where the ident is different.
        -- This can happen if there are multiple unique identifiers, and one is changed or used inconcistently.
        -- {"tax_ident": "1234", stat_ident: "2345"} - First entry
        -- {"tax_ident": "1234", stat_ident: "3456"} - Second entry
        -- It is not clear at this point if they are supposed to be the same entry, and the stat_ident was changed,
        -- or if it is an error with duplicate tax_ident.
        -- In this case there will not be a match for {stat_ident: "3456"}, the conflict is with (type_id, legal_unit_id, establishment_id).

        -- Example from the raise above:
        -- DEBUG:  External identifiers to add:
        -- [
        --   {
        --     "id": null,
        --     "ident": "82212760144",
        --     "type_id": 1,
        --     "enterprise_id": null,
        --     "legal_unit_id": null,
        --     "establishment_id": null,
        --     "updated_by_user_id": null,
        --     "enterprise_group_id": null
        --   }
        -- ]
        --
        WITH identifier_problems AS (
          SELECT DISTINCT
                 CASE
                   WHEN ei.legal_unit_id IS NOT NULL THEN 'legal_unit'
                   WHEN ei.establishment_id IS NOT NULL THEN 'establishment'
                 END AS unit_type
               , eit.code AS code
               , ei.ident AS current_ident
               , new_ei.ident AS new_ident
               , CASE
                   WHEN ei.ident = new_ei.ident THEN 'conflicting_identifier'
                   ELSE 'unstable_identifier'
                 END AS problem
          FROM unnest(external_idents_to_add) AS new_ei
          JOIN public.external_ident AS ei
            ON (ei.type_id = new_ei.type_id AND ei.ident = new_ei.ident)  -- conflicting case
            OR (ei.type_id = new_ei.type_id  -- unstable case
                AND ei.ident <> new_ei.ident
                AND ei.legal_unit_id IS NOT DISTINCT FROM p_legal_unit_id
                AND ei.establishment_id IS NOT DISTINCT FROM p_establishment_id
                )
          JOIN public.external_ident_type AS eit
            ON ei.type_id = eit.id
        )
        SELECT jsonb_agg(
            jsonb_build_object(
              'unit_type', ic.unit_type,
              'code', ic.code,
              'current_ident', ic.current_ident,
              'new_ident', ic.new_ident,
              'problem', ic.problem
            )
        ) INTO identifier_problems_jsonb
        FROM identifier_problems AS ic;

        RAISE EXCEPTION 'Identifier conflicts % for row %', identifier_problems_jsonb, new_jsonb
        USING ERRCODE = 'unique_violation',
          HINT = 'Check for other units already using the same identifier',
          DETAIL = 'Key constraint (type_id, '||unit_type||'_id) is violated.';
      END;
    END;
  END IF;
END;
$insert_external_idents$;

END;
