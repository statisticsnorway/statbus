BEGIN;

CREATE TYPE public.statbus_role_type AS ENUM('super_user','regular_user', 'restricted_user', 'external_user');

CREATE TABLE public.statbus_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type public.statbus_role_type NOT NULL,
    name character varying(256) NOT NULL UNIQUE,
    description text
);
-- There can only ever be one role for most role types.
-- while there can be many different restricted_user roles, depending on the actual restrictions.
CREATE UNIQUE INDEX statbus_role_role_type ON public.statbus_role(type) WHERE type = 'super_user' OR type = 'regular_user' OR type = 'external_user';

CREATE TABLE public.statbus_user (
  id SERIAL PRIMARY KEY,
  uuid uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
  UNIQUE (uuid)
);


-- inserts a row into public.profiles
CREATE FUNCTION admin.create_new_statbus_user()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  role_id INTEGER;
BEGIN
  -- Start with regular user rights upon auto creation by trigger.
  SELECT id INTO role_id FROM public.statbus_role WHERE type = 'regular_user';
  INSERT INTO public.statbus_user (uuid, role_id) VALUES (new.id, role_id);
  RETURN new;
END;
$$;

-- trigger the function every time a user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE admin.create_new_statbus_user();

INSERT INTO public.statbus_role(type, name, description) VALUES ('super_user', 'Super User', 'Can manage all metadata and do everything in the Web interface and manage role rights.');
INSERT INTO public.statbus_role(type, name, description) VALUES ('regular_user', 'Regular User', 'Can do everything in the Web interface.');
INSERT INTO public.statbus_role(type, name, description) VALUES ('restricted_user', 'Restricted User', 'Can see everything and edit according to assigned region and/or activity');
INSERT INTO public.statbus_role(type, name, description) VALUES ('external_user', 'External User', 'Can see selected information');


-- Helper auth functions are found at the end, after relevant tables are defined.

-- Example statbus_role checking
--CREATE POLICY "public view access" ON public_records AS PERMISSIVE FOR SELECT TO public USING (true);
--CREATE POLICY "premium view access" ON premium_records AS PERMISSIVE FOR SELECT TO authenticated USING (
--  has_statbus_role(auth.uid(), 'super_user'::public.statbus_role_type)
--);
--CREATE POLICY "premium and admin view access" ON premium_records AS PERMISSIVE FOR SELECT TO authenticated USING (
--  has_one_of_statbus_roles(auth.uid(), array['super_user', 'restricted_user']::public.statbus_role_type[])
--);


-- Piggyback on auth.users for scalability
-- Ref. https://github.com/supabase-community/supabase-custom-claims
-- and https://github.com/supabase-community/supabase-custom-claims/blob/main/install.sql


-- Use a separate user table, and add a custom permission
-- Ref. https://medium.com/@jimmyruann/row-level-security-custom-permission-base-authorization-with-supabase-91389e6fc48c

-- Use the built in postgres role system to have different roles
-- Ref. https://github.com/orgs/supabase/discussions/11948
-- Create a new role
-- CREATE ROLE new_role_1;
-- -- Allow the login logic to assign this new role
-- GRANT new_role_1 TO authenticator;
-- -- Mark the new role as having the same rights as
-- -- any authenticted person.
-- GRANT authenticated TO new_role_1
-- -- Change the user to use the new role
-- UPDATE auth.users SET role = 'new_role_1' WHERE id = <some-user-uuid>;


-- TODO: Formulate RLS for the roles.
--CREATE POLICY "Public users are viewable by everyone." ON "user" FOR SELECT USING ( true );
--CREATE POLICY "Users can insert their own data." ON "user" FOR INSERT WITH check ( auth.uid() = id );
--CREATE POLICY "Users can update own data." ON "user" FOR UPDATE USING ( auth.uid() = id );


END;
