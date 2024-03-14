DO $$
DECLARE
    census_id integer;
BEGIN

-- Insert root node "Census"
INSERT INTO public.tag (path, name, description, type, context_valid_on, context_valid_from, context_valid_to, is_scoped_tag)
VALUES ('census', 'Census', 'Census data collection', 'custom', NULL, NULL, NULL, false)
RETURNING id INTO census_id;

-- Insert child nodes for each year under "Census"
INSERT INTO public.tag (path, name, description, parent_id, type, context_valid_on, context_valid_from, context_valid_to, is_scoped_tag)
VALUES
('census.2020', '2020', 'Census data for 2020', census_id, 'custom', '2020-12-31', '2020-01-01', 'infinity', false),
('census.2021', '2021', 'Census data for 2021', census_id, 'custom', '2021-12-31', '2021-01-01', 'infinity', false),
('census.2022', '2022', 'Census data for 2022', census_id, 'custom', '2022-12-31', '2022-01-01', 'infinity', false),
('census.2023', '2023', 'Census data for 2023', census_id, 'custom', '2023-12-31', '2023-01-01', 'infinity', false),
('census.2024', '2024', 'Census data for 2024', census_id, 'custom', '2024-12-31', '2024-01-01', 'infinity', false);

END $$;
