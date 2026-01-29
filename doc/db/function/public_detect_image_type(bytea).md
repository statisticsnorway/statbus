```sql
CREATE OR REPLACE FUNCTION public.detect_image_type(data bytea)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE STRICT
 SET search_path TO 'public'
AS $function$
DECLARE
  _len integer;
BEGIN
  _len := octet_length(data);
  
  -- Check each format with minimum length requirements
  -- JPEG: FF D8 FF (3 bytes minimum)
  IF _len >= 3 AND substring(data FROM 1 FOR 3) = '\xffd8ff'::bytea THEN
    RETURN 'image/jpeg';
  END IF;
  
  -- GIF: GIF87a or GIF89a (6 bytes)
  IF _len >= 6 AND (
       substring(data FROM 1 FOR 6) = '\x474946383761'::bytea 
    OR substring(data FROM 1 FOR 6) = '\x474946383961'::bytea
  ) THEN
    RETURN 'image/gif';
  END IF;
  
  -- PNG: 89 50 4E 47 0D 0A 1A 0A (8 bytes)
  IF _len >= 8 AND substring(data FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN
    RETURN 'image/png';
  END IF;
  
  -- WebP: RIFF????WEBP (bytes 1-4 = "RIFF", bytes 9-12 = "WEBP", need 12 bytes)
  IF _len >= 12 
     AND substring(data FROM 1 FOR 4) = '\x52494646'::bytea 
     AND substring(data FROM 9 FOR 4) = '\x57454250'::bytea THEN
    RETURN 'image/webp';
  END IF;
  
  RETURN NULL; -- Unknown format
END;
$function$
```
