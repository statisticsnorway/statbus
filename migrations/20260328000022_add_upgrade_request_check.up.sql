BEGIN;
CREATE FUNCTION public.upgrade_request_check()
RETURNS void LANGUAGE sql SECURITY DEFINER
AS $upgrade_request_check$
  NOTIFY upgrade_check;
$upgrade_request_check$;
END;
