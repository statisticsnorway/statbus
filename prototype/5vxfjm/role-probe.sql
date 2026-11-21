CREATE UNLOGGED TABLE public.z_role_probe(tbl text, cur text, uid int, n bigint default 1);
GRANT ALL ON public.z_role_probe TO PUBLIC;
CREATE FUNCTION public.z_role_probe_f() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO public.z_role_probe(tbl,cur,uid) VALUES (TG_TABLE_NAME, current_user, auth.uid()); RETURN NULL; END $$;
CREATE TRIGGER z_role_probe AFTER INSERT OR UPDATE ON public.legal_unit FOR EACH STATEMENT EXECUTE FUNCTION public.z_role_probe_f();
CREATE TRIGGER z_role_probe AFTER INSERT OR UPDATE ON public.establishment FOR EACH STATEMENT EXECUTE FUNCTION public.z_role_probe_f();
CREATE TRIGGER z_role_probe AFTER INSERT OR UPDATE ON public.activity FOR EACH STATEMENT EXECUTE FUNCTION public.z_role_probe_f();
