```sql
CREATE OR REPLACE PROCEDURE public.quality_check_catalogue_generate()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- One check per per-variable rule and summed variable; an existing check keeps its id and
    -- follows its variable's priority. Ids come in rule then variable order, so a replay gives
    -- the same ids. Only missing checks are inserted: an INSERT ... ON CONFLICT would draw an id
    -- for every existing check on every call.
    UPDATE public.quality_check_catalogue AS qc
    SET priority = array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority
    FROM public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND qc.priority <> array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority;

    INSERT INTO public.quality_check_catalogue (rule, stat_definition_id, kind, priority)
    SELECT r.rule, sd.id, public.quality_rule_kind(r.rule),
           array_position(enum_range(NULL::public.quality_rule), r.rule) * 1000 + sd.priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd ON sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
      AND NOT EXISTS (
          SELECT FROM public.quality_check_catalogue AS qc
          WHERE qc.rule = r.rule AND qc.stat_definition_id = sd.id)
    ORDER BY r.rule, sd.priority, sd.id;
END;
$procedure$
```
