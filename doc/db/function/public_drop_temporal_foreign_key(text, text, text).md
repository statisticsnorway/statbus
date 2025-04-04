```sql
CREATE OR REPLACE FUNCTION public.drop_temporal_foreign_key(constraint_name text, from_table text, to_table text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
  EXECUTE format(
    'DROP TRIGGER %2$s ON %1$s',
    quote_ident(to_table),
    quote_ident(concat('TRI_ConstraintTrigger_a_', constraint_name, '_del')));
  EXECUTE format(
    'DROP TRIGGER %2$s ON %1$s',
    quote_ident(to_table),
    quote_ident(concat('TRI_ConstraintTrigger_a_', constraint_name, '_upd')));
  EXECUTE format(
    'DROP TRIGGER %2$s ON %1$s',
    quote_ident(from_table),
    quote_ident(concat('TRI_ConstraintTrigger_c_', constraint_name, '_ins')));
  EXECUTE format(
    'DROP TRIGGER %2$s ON %1$s',
    quote_ident(from_table),
    quote_ident(concat('TRI_ConstraintTrigger_c_', constraint_name, '_upd')));
END;
$function$
```
