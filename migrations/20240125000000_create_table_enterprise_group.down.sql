BEGIN;

DROP FUNCTION admin.power_group_id_exists(integer);
DROP TABLE public.power_group;
DROP FUNCTION public.generate_power_ident();
DROP SEQUENCE public.power_group_ident_seq;

END;
