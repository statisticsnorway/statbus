```sql
CREATE OR REPLACE FUNCTION admin.prevent_id_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.id <> OLD.id THEN
    RAISE EXCEPTION 'Update of id column in legal_unit table is not allowed!';
  END IF;
  RETURN NEW;
END;
$function$
```
