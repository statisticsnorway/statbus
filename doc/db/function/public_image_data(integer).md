```sql
CREATE OR REPLACE FUNCTION public.image_data(id integer)
 RETURNS "*/*"
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE 
  _headers text;
  _data bytea;
  _type text;
BEGIN
  SELECT i.data, i.type 
  INTO _data, _type
  FROM public.image AS i 
  WHERE i.id = image_data.id;

  IF NOT FOUND THEN
    RAISE sqlstate 'PT404' USING
      message = 'NOT FOUND',
      detail = 'Image not found',
      hint = format('%s is not a valid image id', image_data.id);
  END IF;

  -- Set HTTP headers for proper browser rendering, caching, and security
  -- X-Content-Type-Options: nosniff - Prevents browser from guessing content type
  -- Content-Security-Policy: Blocks script execution if somehow rendered as HTML
  _headers := format(
    '[{"Content-Type": "%s"},'
     '{"Cache-Control": "max-age=604800"},'
     '{"X-Content-Type-Options": "nosniff"},'
     '{"Content-Security-Policy": "default-src ''none''; img-src ''self''"}]',
    COALESCE(_type, 'application/octet-stream')
  );
  
  PERFORM set_config('response.headers', _headers, true);
  
  -- Return binary data directly (stored as bytea)
  RETURN _data;
END;
$function$
```
