```sql
CREATE OR REPLACE FUNCTION public.algorithm_sign(signables text, secret text, algorithm text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
WITH
  alg AS (
    SELECT CASE
      WHEN algorithm = 'HS256' THEN 'sha256'
      WHEN algorithm = 'HS384' THEN 'sha384'
      WHEN algorithm = 'HS512' THEN 'sha512'
      ELSE '' END AS id)  -- hmac throws error
SELECT public.url_encode(public.hmac(signables, secret, alg.id)) FROM alg;
$function$
```
