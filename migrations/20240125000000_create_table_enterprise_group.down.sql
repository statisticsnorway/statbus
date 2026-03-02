BEGIN;

-- Drop power_override trigger and function
DROP TRIGGER IF EXISTS power_override_derive_trigger ON public.power_override;
DROP FUNCTION IF EXISTS public.power_override_queue_derive();

-- Drop sql_saga components for power_override
SELECT sql_saga.drop_for_portion_of_view('public.power_override');

SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.power_override',
    key_name => 'power_override_power_group_valid');

SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.power_override',
    key_name => 'power_override_id_valid');

SELECT sql_saga.drop_era('public.power_override');

-- Drop tables
DROP TABLE public.power_override;
DROP TABLE public.power_root;

-- Drop enum
DROP TYPE public.power_group_root_status;

-- Original drops
DROP FUNCTION admin.power_group_id_exists(integer);
DROP TABLE public.power_group;
DROP FUNCTION public.generate_power_ident();
DROP SEQUENCE public.power_group_ident_seq;

END;
