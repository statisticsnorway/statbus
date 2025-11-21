```sql
CREATE OR REPLACE FUNCTION public.gist_translate_cmptype_btree(integer)
 RETURNS smallint
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/btree_gist', $function$gist_translate_cmptype_btree$function$
```
