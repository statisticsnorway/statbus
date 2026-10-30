BEGIN;

-- Copies an import definition, its steps, source columns and mappings into a
-- new custom definition. System definitions are not editable, so this is how
-- an admin adapts one to a file that gained or lost columns: copy it, then
-- ignore the removed column or map the added one in the copy.
CREATE FUNCTION public.import_definition_copy(
  p_definition_id integer,
  p_name text
)
RETURNS public.import_definition
LANGUAGE plpgsql
SECURITY INVOKER
AS $import_definition_copy$
DECLARE
  v_new public.import_definition;
BEGIN
  INSERT INTO public.import_definition
    (slug, name, note, data_source_id, strategy, mode, valid_time_from,
     enabled, custom, default_retention_period, import_as_null, unique_units)
  SELECT '', p_name, d.note, d.data_source_id, d.strategy, d.mode, d.valid_time_from,
         d.enabled, true, d.default_retention_period, d.import_as_null, d.unique_units
  FROM public.import_definition AS d
  WHERE d.id = p_definition_id
  RETURNING * INTO v_new;

  IF v_new.id IS NULL THEN
    RAISE EXCEPTION 'Import definition % not found', p_definition_id;
  END IF;

  INSERT INTO public.import_definition_step (definition_id, step_id)
  SELECT v_new.id, ds.step_id
  FROM public.import_definition_step AS ds
  WHERE ds.definition_id = p_definition_id;

  INSERT INTO public.import_source_column (definition_id, column_name, priority)
  SELECT v_new.id, sc.column_name, sc.priority
  FROM public.import_source_column AS sc
  WHERE sc.definition_id = p_definition_id;

  -- Source columns are matched by name, the copy has new ids.
  INSERT INTO public.import_mapping
    (definition_id, source_column_id, source_value, source_expression,
     target_data_column_id, is_ignored, target_data_column_purpose)
  SELECT v_new.id, new_sc.id, m.source_value, m.source_expression,
         m.target_data_column_id, m.is_ignored, m.target_data_column_purpose
  FROM public.import_mapping AS m
  LEFT JOIN public.import_source_column AS old_sc ON old_sc.id = m.source_column_id
  LEFT JOIN public.import_source_column AS new_sc
    ON new_sc.definition_id = v_new.id AND new_sc.column_name = old_sc.column_name
  WHERE m.definition_id = p_definition_id;

  SELECT * INTO v_new FROM public.import_definition WHERE id = v_new.id;
  RETURN v_new;
END;
$import_definition_copy$;

-- Adds one source column to an existing definition, after its current
-- columns. With p_ignored the column is accepted and ignored on purpose: an
-- upload with it succeeds without a warning. Otherwise it is mapped to the
-- data column <name>_raw of one of the definition's steps, when one exists.
CREATE FUNCTION public.import_definition_add_source_column(
  p_definition_id integer,
  p_column_name text,
  p_ignored boolean DEFAULT false
)
RETURNS public.import_mapping
LANGUAGE plpgsql
SECURITY INVOKER
AS $import_definition_add_source_column$
DECLARE
  v_source_column_id integer;
  v_data_column_id integer;
  v_mapping public.import_mapping;
BEGIN
  INSERT INTO public.import_source_column (definition_id, column_name, priority)
  SELECT p_definition_id, p_column_name, COALESCE(MAX(sc.priority), 0) + 1
  FROM public.import_source_column AS sc
  WHERE sc.definition_id = p_definition_id
  RETURNING id INTO v_source_column_id;

  IF NOT p_ignored THEN
    SELECT dc.id INTO v_data_column_id
    FROM public.import_definition_step AS ds
    JOIN public.import_data_column AS dc ON dc.step_id = ds.step_id
    WHERE ds.definition_id = p_definition_id
      AND dc.column_name = p_column_name || '_raw'
      AND dc.purpose = 'source_input';
    IF v_data_column_id IS NULL THEN
      RAISE EXCEPTION 'No import step of this definition reads a column %', p_column_name
        USING HINT = 'Add it as ignored, or enable the statistical variable or identifier it names.';
    END IF;
  END IF;

  INSERT INTO public.import_mapping
    (definition_id, source_column_id, target_data_column_id, is_ignored, target_data_column_purpose)
  VALUES
    (p_definition_id, v_source_column_id, v_data_column_id, p_ignored,
     CASE WHEN p_ignored THEN NULL ELSE 'source_input'::public.import_data_column_purpose END)
  RETURNING * INTO v_mapping;
  RETURN v_mapping;
END;
$import_definition_add_source_column$;

END;
