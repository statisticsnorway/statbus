DO $$
DECLARE
    census_id integer;
BEGIN

    -- UPSERT root node "Census"
    INSERT INTO public.tag (path, name, description, type, context_valid_on, context_valid_from, context_valid_to, is_scoped_tag)
    VALUES ('census', 'Census', 'Census data collection', 'custom', NULL, NULL, NULL, false)
    ON CONFLICT (path) DO UPDATE
    SET name = EXCLUDED.name, description = EXCLUDED.description, type = EXCLUDED.type,
        context_valid_on = EXCLUDED.context_valid_on, context_valid_from = EXCLUDED.context_valid_from,
        context_valid_to = EXCLUDED.context_valid_to, is_scoped_tag = EXCLUDED.is_scoped_tag
    RETURNING id INTO census_id;

    -- UPSERT child nodes for each year under "Census"
    INSERT INTO public.tag (path, name, description, parent_id, type, context_valid_on, context_valid_from, context_valid_to, is_scoped_tag)
    VALUES
    ('census.2015', '2015', 'Census data for 2015', census_id, 'custom', '2015-12-31', '2015-01-01', 'infinity', false),
    ('census.2016', '2016', 'Census data for 2016', census_id, 'custom', '2016-12-31', '2016-01-01', 'infinity', false),
    ('census.2017', '2017', 'Census data for 2017', census_id, 'custom', '2017-12-31', '2017-01-01', 'infinity', false),
    ('census.2018', '2018', 'Census data for 2018', census_id, 'custom', '2018-12-31', '2018-01-01', 'infinity', false),
    ('census.2019', '2019', 'Census data for 2019', census_id, 'custom', '2019-12-31', '2019-01-01', 'infinity', false),
    ('census.2020', '2020', 'Census data for 2020', census_id, 'custom', '2020-12-31', '2020-01-01', 'infinity', false),
    ('census.2021', '2021', 'Census data for 2021', census_id, 'custom', '2021-12-31', '2021-01-01', 'infinity', false),
    ('census.2022', '2022', 'Census data for 2022', census_id, 'custom', '2022-12-31', '2022-01-01', 'infinity', false),
    ('census.2023', '2023', 'Census data for 2023', census_id, 'custom', '2023-12-31', '2023-01-01', 'infinity', false),
    ('census.2024', '2024', 'Census data for 2024', census_id, 'custom', '2024-12-31', '2024-01-01', 'infinity', false)
    ON CONFLICT (path) DO UPDATE
    SET name = EXCLUDED.name, description = EXCLUDED.description, parent_id = EXCLUDED.parent_id, type = EXCLUDED.type,
        context_valid_on = EXCLUDED.context_valid_on, context_valid_from = EXCLUDED.context_valid_from,
        context_valid_to = EXCLUDED.context_valid_to, is_scoped_tag = EXCLUDED.is_scoped_tag;

END $$;
