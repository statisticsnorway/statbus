BEGIN;

CREATE OR REPLACE FUNCTION admin.check_stat_for_unit_values()
RETURNS trigger AS $$
DECLARE
  new_type public.stat_type;
BEGIN
  -- Fetch the type for the current stat_definition_id
  SELECT type INTO new_type
  FROM public.stat_definition
  WHERE id = NEW.stat_definition_id;

  -- Use CASE statement to simplify the logic
  CASE new_type
    WHEN 'int' THEN
      IF NEW.value_int IS NULL OR NEW.value_float IS NOT NULL OR NEW.value_string IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    WHEN 'float' THEN
      IF NEW.value_float IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_string IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    WHEN 'string' THEN
      IF NEW.value_string IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_float IS NOT NULL OR NEW.value_bool IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    WHEN 'bool' THEN
      IF NEW.value_bool IS NULL OR NEW.value_int IS NOT NULL OR NEW.value_float IS NOT NULL OR NEW.value_string IS NOT NULL THEN
        RAISE EXCEPTION 'Incorrect value columns set for type %s', new_type;
      END IF;
    ELSE
      RAISE EXCEPTION 'Unknown type: %', new_type;
  END CASE;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_stat_for_unit_values_trigger
BEFORE INSERT OR UPDATE ON public.stat_for_unit
FOR EACH ROW EXECUTE FUNCTION admin.check_stat_for_unit_values();

END;
