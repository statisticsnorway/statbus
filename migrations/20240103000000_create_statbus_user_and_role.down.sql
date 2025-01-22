BEGIN;

DROP TRIGGER on_auth_user_created ON auth.users;

DROP FUNCTION admin.create_new_statbus_user();

DROP TABLE public.statbus_user;
DROP TABLE public.statbus_role;
-- Clear out any users possibly left after removal of statbus_user.
DELETE FROM auth.users;

DROP TYPE public.statbus_role_type;

END;
