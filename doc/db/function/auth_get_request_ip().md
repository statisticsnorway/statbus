```sql
CREATE OR REPLACE FUNCTION auth.get_request_ip()
 RETURNS inet
 LANGUAGE plpgsql
AS $function$
DECLARE
  raw_ip_text text;
BEGIN
  -- Extract the first IP from X-Forwarded-For header
  raw_ip_text := split_part(nullif(current_setting('request.headers', true),'')::json->>'x-forwarded-for', ',', 1);
  
  IF raw_ip_text IS NOT NULL AND raw_ip_text != '' THEN
    -- Conditionally strip port:
    -- Only if a colon is present AND the string ends with :digits.
    IF raw_ip_text LIKE '%:%' AND raw_ip_text ~ ':\d+$' THEN
      DECLARE
        temp_ip_after_port_strip text;
      BEGIN
        temp_ip_after_port_strip := regexp_replace(raw_ip_text, ':\d+$', '');
        -- If stripping the port results in just ":" or "" (empty string),
        -- it means the original was likely a short IPv6 like "::1" or an invalid IP.
        -- In this case, don't use the stripped version; let inet() parse the original.
        IF temp_ip_after_port_strip <> ':' AND temp_ip_after_port_strip <> '' THEN
          raw_ip_text := temp_ip_after_port_strip;
        END IF;
      END;
    END IF;
    
    -- Unconditionally strip brackets if present on the (potentially) port-stripped IP.
    -- inet() does not accept brackets around IPv6 addresses.
    IF raw_ip_text ~ '^\[.+\]$' THEN
      raw_ip_text := substring(raw_ip_text from 2 for length(raw_ip_text) - 2);
    END IF;
    
    RETURN inet(raw_ip_text);
  ELSE
    RETURN NULL;
  END IF;
  -- Errors from inet() conversion (e.g., invalid IP format) will propagate.
END;
$function$
```
