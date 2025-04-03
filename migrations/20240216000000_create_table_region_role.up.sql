BEGIN;

CREATE TABLE public.region_access (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE CASCADE,
    region_id integer NOT NULL REFERENCES public.region(id) ON DELETE CASCADE,
    UNIQUE(user_id, region_id)
);
CREATE INDEX ix_region_access_region_id ON public.region_access USING btree (region_id);
CREATE INDEX ix_region_access_user_id ON public.region_access USING btree (user_id);

-- Enable RLS on the region_access table
ALTER TABLE public.region_access ENABLE ROW LEVEL SECURITY;

-- Create policy for admin_user to have full access
CREATE POLICY region_access_admin_policy ON public.region_access 
    FOR ALL TO admin_user USING (true) WITH CHECK (true);

-- Create policy for read-only access for authenticated users
CREATE POLICY region_access_read_policy ON public.region_access 
    FOR SELECT TO authenticated USING (true);

END;
