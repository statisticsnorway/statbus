BEGIN;

-- Domain for binary responses with any content type
CREATE DOMAIN public."*/*" AS bytea;

-- Function to serve image with proper HTTP headers for browsers
CREATE FUNCTION public.image_data(id integer) 
RETURNS public."*/*" 
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $image_data$
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

  -- Set HTTP headers for proper browser rendering and caching
  _headers := format(
    '[{"Content-Type": "%s"},'
     '{"Cache-Control": "max-age=604800"}]',  -- 7 days cache
    COALESCE(_type, 'application/octet-stream')
  );
  
  PERFORM set_config('response.headers', _headers, true);
  
  -- Return binary data directly (stored as bytea)
  RETURN _data;
END;
$image_data$;

COMMENT ON FUNCTION public.image_data(integer) IS 
  'Serves image data via PostgREST with proper Content-Type and Cache-Control headers. Usage: /rest/rpc/image_data?id=42';

COMMIT;
