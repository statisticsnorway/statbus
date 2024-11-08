```sql
CREATE OR REPLACE FUNCTION admin.insert_external_idents(new_jsonb jsonb, external_idents_to_add external_ident[], p_legal_unit_id integer, p_establishment_id integer, p_updated_by_user_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  unit_type TEXT;
BEGIN
  -- Ensure that either legal_unit_id or establishment_id is provided, but not both.
  IF (p_legal_unit_id IS NOT NULL AND p_establishment_id IS NOT NULL) OR
      (p_legal_unit_id IS NULL AND p_establishment_id IS NULL) THEN
      RAISE EXCEPTION 'Must provide either a p_legal_unit_id or an p_establishment_id, but not both.';
  END IF;

  IF array_length(external_idents_to_add, 1) > 0 THEN
    BEGIN
      IF p_legal_unit_id IS NOT NULL THEN
        unit_type := 'legal_unit';
        -- Insert for legal units if legal_unit_id is provided.
        INSERT INTO public.external_ident
            ( type_id
            , ident
            , legal_unit_id
            , updated_by_user_id
            )
        SELECT type_id
              , ident
              , p_legal_unit_id
              , p_updated_by_user_id
        FROM unnest(external_idents_to_add);
      ELSIF p_establishment_id IS NOT NULL THEN
        unit_type := 'establishment';
        -- Insert for establishments if establishment_id is provided.
        INSERT INTO public.external_ident
            ( type_id
            , ident
            , establishment_id
            , updated_by_user_id
            )
        SELECT type_id
              , ident
              , p_establishment_id
              , p_updated_by_user_id
        FROM unnest(external_idents_to_add);
      END IF;
    EXCEPTION WHEN unique_violation THEN
      IF SQLERRM LIKE '%external_ident_type_for_%' THEN
        DECLARE
          pg_exception_detail	TEXT;

          extracted_values TEXT[];

          extracted_conflict_unit_type TEXT;
          extracted_foreign_column TEXT;
          extracted_type_id INTEGER;
          extracted_unit_id INTEGER;
          offending_rows JSONB;

        BEGIN
          GET STACKED DIAGNOSTICS pg_exception_detail = PG_EXCEPTION_DETAIL;

          -- pg_exception_detail='Key (type_id, establishment_id)=(1, 1) already exists.'
          extracted_values := regexp_matches(
              pg_exception_detail,
              'Key \(type_id, ((.*?)_id)\)=\((\d+), (\d+)\)'
          );

          IF array_length(extracted_values, 1) = 4 THEN
            extracted_foreign_column := extracted_values[1];
            extracted_conflict_unit_type := extracted_values[2];
            extracted_type_id := extracted_values[3]::INT;
            extracted_unit_id := extracted_values[4]::INT;

            EXECUTE format($$
              SELECT jsonb_object_agg(eit.code,ei.ident)
              FROM public.external_ident AS ei
              JOIN public.external_ident_type AS eit
              ON ei.type_id = eit.id
              WHERE ei.%s = %L
            $$, extracted_foreign_column, extracted_unit_id)
            INTO offending_rows;

            RAISE EXCEPTION 'Another % % already uses the same identier(s) as the % in row %', extracted_conflict_unit_type, offending_rows, unit_type, new_jsonb
            USING ERRCODE = 'unique_violation',
              HINT = 'Check for other units already using the same identifier',
              DETAIL = 'Key constraint (type_id, '||unit_type||'_id) is violated.';
          ELSE
              RAISE EXCEPTION 'Another unit already uses the same identier(s) as the % in row %', unit_type, new_jsonb;
          END IF;
        END;
      ELSE
        RAISE EXCEPTION 'Another unit already uses the same identier(s) as the % in row %', unit_type, new_jsonb;
      END IF;
    END;
  END IF;
END;
$function$
```
