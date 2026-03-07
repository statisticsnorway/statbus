```sql
CREATE OR REPLACE FUNCTION public.generate_power_ident()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    _seq_val bigint;
    _chars text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    _base integer := 36;
    _result text := '';
BEGIN
    _seq_val := nextval('public.power_group_ident_seq');
    
    WHILE _seq_val > 0 LOOP
        _result := substr(_chars, (_seq_val % _base)::integer + 1, 1) || _result;
        _seq_val := _seq_val / _base;
    END LOOP;
    
    _result := lpad(COALESCE(NULLIF(_result, ''), '0'), 4, '0');
    RETURN 'PG' || _result;
END;
$function$
```
