```sql
CREATE OR REPLACE FUNCTION public.legal_relationship_set_primary_influencer_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    SELECT lrt.primary_influencer_only INTO NEW.primary_influencer_only
    FROM public.legal_rel_type AS lrt WHERE lrt.id = NEW.type_id;
    RETURN NEW;
END;
$function$
```
