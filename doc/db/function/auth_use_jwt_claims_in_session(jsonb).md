```sql
CREATE OR REPLACE FUNCTION auth.use_jwt_claims_in_session(claims jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Store the full claims object
  PERFORM set_config('request.jwt.claims', claims::text, true);
END;
$function$
```
