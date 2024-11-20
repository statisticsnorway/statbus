-- Add security.

\echo auth.has_statbus_role
CREATE OR REPLACE FUNCTION auth.has_statbus_role (user_uuid UUID, type public.statbus_role_type)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT EXISTS (
    SELECT su.id
    FROM public.statbus_user AS su
    JOIN public.statbus_role AS sr
      ON su.role_id = sr.id
    WHERE ((su.uuid = $1) AND (sr.type = $2))
  );
$$;

-- Add security functions
\echo auth.has_one_of_statbus_roles
CREATE OR REPLACE FUNCTION auth.has_one_of_statbus_roles (user_uuid UUID, types public.statbus_role_type[])
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT EXISTS (
    SELECT su.id
    FROM public.statbus_user AS su
    JOIN public.statbus_role AS sr
      ON su.role_id = sr.id
    WHERE ((su.uuid = $1) AND (sr.type = ANY ($2)))
  );
$$;


\echo auth.has_activity_category_access
CREATE OR REPLACE FUNCTION auth.has_activity_category_access (user_uuid UUID, activity_category_id integer)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
    SELECT EXISTS(
        SELECT su.id
        FROM public.statbus_user AS su
        INNER JOIN public.activity_category_role AS acr ON acr.role_id = su.role_id
        WHERE su.uuid = $1
          AND acr.activity_category_id  = $2
   )
$$;


CREATE OR REPLACE FUNCTION auth.has_region_access (user_uuid UUID, region_id integer)
RETURNS BOOL
LANGUAGE SQL
SECURITY DEFINER
AS
$$
    SELECT EXISTS(
        SELECT su.id
        FROM public.statbus_user AS su
        INNER JOIN public.region_role AS rr ON rr.role_id = su.role_id
        WHERE su.uuid = $1
          AND rr.region_id  = $2
   )
$$;