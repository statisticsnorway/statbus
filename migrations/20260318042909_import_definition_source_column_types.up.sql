BEGIN;

CREATE FUNCTION public.import_definition_source_column_types(p_definition_id integer)
RETURNS TABLE(column_name text, column_type text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $import_definition_source_column_types$
  SELECT isc.column_name, COALESCE(idc_int.column_type, 'TEXT') AS column_type
  FROM import_source_column AS isc
  JOIN import_mapping AS im ON im.source_column_id = isc.id AND NOT im.is_ignored
  JOIN import_data_column AS idc_raw ON idc_raw.id = im.target_data_column_id
  LEFT JOIN import_data_column AS idc_int
    ON idc_int.step_id = idc_raw.step_id
    AND idc_int.purpose = 'internal'
    AND idc_int.column_name = replace(idc_raw.column_name, '_raw', '')
  WHERE isc.definition_id = p_definition_id
  ORDER BY isc.priority;
$import_definition_source_column_types$;

END;
