```sql
CREATE OR REPLACE FUNCTION public.validate_image_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  _detected_type text;
BEGIN
  _detected_type := public.detect_image_type(NEW.data);
  
  IF _detected_type IS NULL THEN
    RAISE EXCEPTION 'Invalid image data: unrecognized file format'
      USING HINT = 'Supported formats: PNG, JPEG, GIF, WebP. SVG is not allowed due to security restrictions.',
            ERRCODE = 'check_violation';
  END IF;
  
  -- Auto-correct the MIME type to match actual content
  -- This prevents attackers from uploading valid images with malicious Content-Type
  NEW.type := _detected_type;
  
  RETURN NEW;
END;
$function$
```
