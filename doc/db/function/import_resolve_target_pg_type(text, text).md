```sql
CREATE OR REPLACE FUNCTION import.resolve_target_pg_type(p_step_code text, p_column_name text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_table_name text;
    v_column_name text;
    v_resolved_type text;
BEGIN
    -- Map (import_step.code, import_data_column.column_name) → the
    -- canonical PostgreSQL type string of the corresponding
    -- public.<table>.<column>, when such a mapping exists. Returns
    -- NULL for columns with no public.* counterpart (purely-internal
    -- import machinery like 'operation', 'action',
    -- 'primary_for_enterprise', or FK ids that resolve to *_id
    -- columns on the parent table).
    CASE
        WHEN p_step_code = 'physical_location' AND p_column_name LIKE 'physical_%' THEN
            v_table_name := 'location';
            v_column_name := substring(p_column_name from 10); -- strip 'physical_'
        WHEN p_step_code = 'postal_location' AND p_column_name LIKE 'postal_%' THEN
            v_table_name := 'location';
            v_column_name := substring(p_column_name from 8);  -- strip 'postal_'
        WHEN p_step_code = 'primary_activity' AND p_column_name LIKE 'primary_%' THEN
            v_table_name := 'activity';
            v_column_name := substring(p_column_name from 9);  -- strip 'primary_'
        WHEN p_step_code = 'secondary_activity' AND p_column_name LIKE 'secondary_%' THEN
            v_table_name := 'activity';
            v_column_name := substring(p_column_name from 11); -- strip 'secondary_'
        WHEN p_step_code IN ('legal_unit', 'establishment', 'contact',
                              'data_source', 'status', 'legal_relationship') THEN
            v_table_name := p_step_code;
            v_column_name := p_column_name;
        WHEN p_step_code = 'external_idents' THEN
            v_table_name := 'external_ident';
            v_column_name := p_column_name;
        WHEN p_step_code = 'tags' THEN
            v_table_name := 'tag';
            v_column_name := p_column_name;
        WHEN p_step_code = 'edit_info' AND p_column_name LIKE 'edit_%' THEN
            -- edit_* columns appear on every unit/sub-unit table with
            -- identical types (edit_comment varchar(512), edit_at
            -- timestamptz, edit_by_user_id integer). public.legal_unit
            -- is the canonical source.
            v_table_name := 'legal_unit';
            v_column_name := p_column_name;
        ELSE
            RETURN NULL;
    END CASE;

    SELECT format_type(a.atttypid, a.atttypmod)
    INTO v_resolved_type
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = v_table_name
      AND a.attname = v_column_name
      AND NOT a.attisdropped
      AND a.attnum > 0;

    RETURN v_resolved_type;
END;
$function$
```
