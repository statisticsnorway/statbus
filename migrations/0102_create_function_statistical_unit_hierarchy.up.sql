\echo public.statistical_unit_hierarchy
CREATE OR REPLACE FUNCTION public.statistical_unit_hierarchy(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT --jsonb_strip_nulls(
            public.enterprise_hierarchy(
              public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
              , valid_on
            )
        --)
;
$$;