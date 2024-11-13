```sql
CREATE OR REPLACE FUNCTION admin.legal_unit_brreg_view_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  result RECORD;
BEGIN
    WITH su AS (
        SELECT *
        FROM statbus_user
        WHERE uuid = auth.uid()
        LIMIT 1
    ), upsert_data AS (
        SELECT
          NEW."organisasjonsnummer" AS tax_ident
        , '2023-01-01'::date AS valid_from
        , 'infinity'::date AS valid_to
        , CASE NEW."stiftelsesdato"
          WHEN NULL THEN NULL
          WHEN '' THEN NULL
          ELSE NEW."stiftelsesdato"::date
          END AS birth_date
        , NEW."navn" AS name
        , true AS active
        , 'Batch import' AS edit_comment
        , (SELECT id FROM su) AS edit_by_user_id
    ),
    update_outcome AS (
        UPDATE public.legal_unit
        SET valid_from = upsert_data.valid_from
          , valid_to = upsert_data.valid_to
          , birth_date = upsert_data.birth_date
          , name = upsert_data.name
          , active = upsert_data.active
          , edit_comment = upsert_data.edit_comment
          , edit_by_user_id = upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE legal_unit.tax_ident = upsert_data.tax_ident
          AND legal_unit.valid_to = 'infinity'::date
        RETURNING 'update'::text AS action, legal_unit.id
    ),
    insert_outcome AS (
        INSERT INTO public.legal_unit
          ( tax_ident
          , valid_from
          , valid_to
          , birth_date
          , name
          , active
          , edit_comment
          , edit_by_user_id
          )
        SELECT
            upsert_data.tax_ident
          , upsert_data.valid_from
          , upsert_data.valid_to
          , upsert_data.birth_date
          , upsert_data.name
          , upsert_data.active
          , upsert_data.edit_comment
          , upsert_data.edit_by_user_id
        FROM upsert_data
        WHERE NOT EXISTS (SELECT id FROM update_outcome LIMIT 1)
        RETURNING 'insert'::text AS action, id
    ), combined AS (
      SELECT * FROM update_outcome UNION ALL SELECT * FROM insert_outcome
    )
    SELECT * INTO result FROM combined;
    RETURN NULL;
END;
$function$
```
