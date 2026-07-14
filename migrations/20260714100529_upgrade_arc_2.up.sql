-- Upgrade-arc healthpark fixture V2 (STATBUS-145 doc-029): deterministic
-- health-check break. Preserves auth_status's exact signature (schema-cache
-- introspection / PostgREST /ready is unaffected) but the body now RAISEs on
-- every call, so the post-swap health leg's functional RPC probe
-- (/rpc/auth_status, after /ready warmup passes) fails deterministically.
-- This migration itself SUCCEEDS — the box is genuinely at-target when the
-- upgrade parks. NEVER fix by editing this file in place (see V3 / doc-029
-- Rev 2): a release-channel content_hash mismatch on an already-applied
-- version is BLESSED (re-stamped, never re-run), not re-executed.
CREATE OR REPLACE FUNCTION public.auth_status()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION 'upgrade-arc healthpark fixture (STATBUS-145): deterministic health-check failure — auth_status intentionally broken';
END;
$function$;
