BEGIN;

-- Delete static data columns associated with the steps being removed
DELETE FROM public.import_data_column
WHERE step_id IN (
    SELECT id FROM public.import_step WHERE code IN (
        'external_idents', 'valid_time', 'status',
        'enterprise_link_for_legal_unit', 'enterprise_link_for_establishment',
        'legal_unit', 'establishment', 'link_establishment_to_legal_unit',
        'physical_location', 'postal_location', 'primary_activity', 'secondary_activity',
        'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'
    )
);

-- Delete the import steps
DELETE FROM public.import_step
WHERE code IN (
    'external_idents', 'valid_time', 'status',
    'enterprise_link_for_legal_unit', 'enterprise_link_for_establishment',
    'legal_unit', 'establishment', 'link_establishment_to_legal_unit',
    'physical_location', 'postal_location', 'primary_activity', 'secondary_activity',
    'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'
);

COMMIT;
