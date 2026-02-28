-- Create import definition for BRREG Roller (legal relationships) using 2025 columns
-- This imports org-to-org controlling relationships extracted from BRREG roller data.

DO $$
DECLARE
    def_id INT;
    -- Steps for legal_relationship mode (no external_idents - identities resolved within legal_relationship step)
    lr_steps TEXT[] := ARRAY['valid_time', 'legal_relationship', 'edit_info', 'metadata'];
    -- Source columns matching the CSV header from extract-roller-to-csv.py
    lr_source_cols TEXT[] := ARRAY[
        'influencing_tax_ident', 'influenced_tax_ident',
        'rel_type_code', 'percentage'
    ];
BEGIN
    -- 0. Drop the definition if it exists, to ensure a clean slate.
    --    This will cascade and remove related jobs and tables.
    DELETE FROM public.import_definition WHERE slug = 'brreg_roller_2025';

    -- 1. Create the definition record (initially invalid)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id)
    VALUES (
        'brreg_roller_2025',
        'Import of BRREG Roller (legal relationships) using 2025 columns',
        'Import org-to-org controlling relationships from BRREG roller data.',
        'insert_or_update',
        'legal_relationship',
        'job_provided',
        false,
        (SELECT id FROM public.data_source WHERE code = 'brreg')
    )
    RETURNING id INTO def_id;

    -- 2. Link the required steps to the definition
    PERFORM import.link_steps_to_definition(def_id, lr_steps);

    -- 3. Create source columns and mappings using the helper function
    PERFORM import.create_source_and_mappings_for_definition(def_id, lr_source_cols);

END $$;

-- Display the created definition details
SELECT d.slug,
       d.name,
       d.note,
       ds.code as data_source,
       d.valid_time_from,
       d.strategy,
       d.valid,
       d.validation_error
FROM public.import_definition d
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id
WHERE d.slug = 'brreg_roller_2025';

-- Validate and set the definition to valid
SELECT admin.validate_import_definition(id) FROM public.import_definition WHERE slug = 'brreg_roller_2025';

-- Show final validation state
SELECT d.slug, d.valid, d.validation_error
FROM public.import_definition d
WHERE d.slug = 'brreg_roller_2025';
