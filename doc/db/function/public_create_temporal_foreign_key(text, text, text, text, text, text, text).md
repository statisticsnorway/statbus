```sql
CREATE OR REPLACE FUNCTION public.create_temporal_foreign_key(constraint_name text, from_table text, from_column text, from_range_column text, to_table text, to_column text, to_range_column text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  fk_val INTEGER;
  from_range anyrange;
BEGIN

  -- TODO: Support CASCADE/SET NULL/SET DEFAULT:
  -- TODO: These should be deferrable to support moving a change's time.
  -- TODO: I should probably have some kind of normalize operation....
  -- Using the name like this is not ideal since it means `constraint_name` can't be 63 chars.
  -- The built-in FKs save the user-provided name for the constraint,
  -- and then create internal constraint triggers as a two-step process,
  -- so they get the constraint trigger's oid before saving the name.
  -- Oh well, there is still lots of room.
  -- If we wanted to maintain our own catalog we could make it an oid-enabled table,
  -- and then we could use the single "temporal foreign key constraint" oid
  -- to name these triggers.

  -- Check the PK when it's DELETEd:
  EXECUTE format($q$
    CREATE CONSTRAINT TRIGGER %1$s
    AFTER DELETE ON %2$s
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE TRI_FKey_restrict_del(%3$s, %4$s, %5$s, %6$s, %7$s, %8$s)
    $q$,
    quote_ident(concat('TRI_ConstraintTrigger_a_', constraint_name, '_del')),
    quote_ident(to_table),
    quote_nullable(from_table),
    quote_nullable(from_column),
    quote_nullable(from_range_column),
    quote_nullable(to_table),
    quote_nullable(to_column),
    quote_nullable(to_range_column));

  -- TODO: Support CASCASE/SET NULL/SET DEFAULT:
  -- Check the PK when it's UPDATEd:
  EXECUTE format($q$
    CREATE CONSTRAINT TRIGGER %1$s
    AFTER UPDATE ON %2$s
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE TRI_FKey_restrict_upd(%3$s, %4$s, %5$s, %6$s, %7$s, %8$s)
    $q$,
    quote_ident(concat('TRI_ConstraintTrigger_a_', constraint_name, '_upd')),
    quote_ident(to_table),
    quote_nullable(from_table),
    quote_nullable(from_column),
    quote_nullable(from_range_column),
    quote_nullable(to_table),
    quote_nullable(to_column),
    quote_nullable(to_range_column));

  -- Check the FK when it's INSERTed:
  EXECUTE format($q$
    CREATE CONSTRAINT TRIGGER %1$s
    AFTER INSERT ON %2$s
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE TRI_FKey_check_ins(%3$s, %4$s, %5$s, %6$s, %7$s, %8$s)
    $q$,
    quote_ident(concat('TRI_ConstraintTrigger_c_', constraint_name, '_ins')),
    quote_ident(from_table),
    quote_nullable(from_table),
    quote_nullable(from_column),
    quote_nullable(from_range_column),
    quote_nullable(to_table),
    quote_nullable(to_column),
    quote_nullable(to_range_column));

  -- Check the FK when it's UPDATEd:
  EXECUTE format($q$
    CREATE CONSTRAINT TRIGGER %1$s
    AFTER UPDATE ON %2$s
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE TRI_FKey_check_upd(%3$s, %4$s, %5$s, %6$s, %7$s, %8$s)
    $q$,
    quote_ident(concat('TRI_ConstraintTrigger_c_', constraint_name, '_upd')),
    quote_ident(from_table),
    quote_nullable(from_table),
    quote_nullable(from_column),
    quote_nullable(from_range_column),
    quote_nullable(to_table),
    quote_nullable(to_column),
    quote_nullable(to_range_column));

  -- Validate all the existing rows.
  --   The built-in FK triggers do this one-by-one instead of with a big query,
  --   which seems less efficient, but it does have better code reuse.
  --   I'm following their lead here:
  FOR fk_val, from_range IN EXECUTE format(
    'SELECT %2$s, %3$s FROM %1$s',
    quote_ident(from_table), quote_ident(from_column), quote_ident(from_range_column)
  ) LOOP
    PERFORM TRI_FKey_check(
      from_table, from_column, from_range_column,
      to_table,   to_column,   to_range_column,
      fk_val, from_range, false);
  END LOOP;

  -- TODO: Keep it in a catalog?
END;
$function$
```
