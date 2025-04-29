-- Migration 20250228000000: generate_default_import_definitions
BEGIN;

-- Create default import definitions for all target tables

-- 1. Legal unit with time_context for current year
WITH legal_unit_target AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_legal_unit_era'
), legal_unit_current_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        , time_context_ident
        )
    SELECT legal_unit_target.id
        , 'legal_unit_current_year'
        , 'Legal Unit - Current Year'
        , 'Import legal units with validity period set to current year'
        , 'r_year_curr'
    FROM legal_unit_target
    RETURNING *
), legal_unit_current_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT legal_unit_current_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM legal_unit_current_def
    JOIN public.import_target_column itc ON itc.target_id = legal_unit_current_def.target_id
    WHERE itc.column_name NOT IN ('valid_from', 'valid_to')
    RETURNING *
), legal_unit_current_mappings AS (
    -- Map source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT legal_unit_current_def.id, sc.id, tc.id, NULL, NULL
    FROM legal_unit_current_def
    JOIN legal_unit_current_source_columns sc ON sc.definition_id = legal_unit_current_def.id
    JOIN public.import_target_column tc ON tc.target_id = legal_unit_current_def.target_id AND tc.column_name = sc.column_name

    UNION ALL

    -- Add default mappings for valid_from and valid_to
    SELECT legal_unit_current_def.id, NULL, tc.id, NULL, 'default'::public.import_source_expression
    FROM legal_unit_current_def
    JOIN public.import_target_column tc ON tc.target_id = legal_unit_current_def.target_id
    WHERE tc.column_name IN ('valid_from', 'valid_to')
    RETURNING *
),

-- 2. Legal unit with explicit valid_from/valid_to
legal_unit_explicit_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT legal_unit_target.id
        , 'legal_unit_explicit_dates'
        , 'Legal Unit - Explicit Dates'
        , 'Import legal units with explicit valid_from and valid_to columns'
    FROM legal_unit_target
    RETURNING *
), legal_unit_explicit_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT legal_unit_explicit_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM legal_unit_explicit_def
    JOIN public.import_target_column itc ON itc.target_id = legal_unit_explicit_def.target_id
    RETURNING *
), legal_unit_explicit_mappings AS (
    -- Map all source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT legal_unit_explicit_def.id, sc.id, tc.id, NULL, NULL
    FROM legal_unit_explicit_def
    JOIN legal_unit_explicit_source_columns sc ON sc.definition_id = legal_unit_explicit_def.id
    JOIN public.import_target_column tc ON tc.target_id = legal_unit_explicit_def.target_id AND tc.column_name = sc.column_name
    RETURNING *
),

-- 3. Establishment for legal unit with time_context for current year
establishment_for_lu_target AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_establishment_era_for_legal_unit'
), establishment_for_lu_current_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        , time_context_ident
        )
    SELECT establishment_for_lu_target.id
        , 'establishment_for_lu_current_year'
        , 'Establishment for Legal Unit - Current Year'
        , 'Import establishments linked to legal units with validity period set to current year'
        , 'r_year_curr'
    FROM establishment_for_lu_target
    RETURNING *
), establishment_for_lu_current_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_for_lu_current_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_for_lu_current_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_for_lu_current_def.target_id
    WHERE itc.column_name NOT IN ('valid_from', 'valid_to')
    RETURNING *
), establishment_for_lu_current_mappings AS (
    -- Map source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_for_lu_current_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_for_lu_current_def
    JOIN establishment_for_lu_current_source_columns sc ON sc.definition_id = establishment_for_lu_current_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_for_lu_current_def.target_id AND tc.column_name = sc.column_name

    UNION ALL

    -- Add default mappings for valid_from and valid_to
    SELECT establishment_for_lu_current_def.id, NULL, tc.id, NULL, 'default'::public.import_source_expression
    FROM establishment_for_lu_current_def
    JOIN public.import_target_column tc ON tc.target_id = establishment_for_lu_current_def.target_id
    WHERE tc.column_name IN ('valid_from', 'valid_to')
    RETURNING *
),

-- 4. Establishment for legal unit with explicit valid_from/valid_to
establishment_for_lu_explicit_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT establishment_for_lu_target.id
        , 'establishment_for_lu_explicit_dates'
        , 'Establishment for Legal Unit - Explicit Dates'
        , 'Import establishments linked to legal units with explicit valid_from and valid_to columns'
    FROM establishment_for_lu_target
    RETURNING *
), establishment_for_lu_explicit_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_for_lu_explicit_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_for_lu_explicit_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_for_lu_explicit_def.target_id
    RETURNING *
), establishment_for_lu_explicit_mappings AS (
    -- Map all source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_for_lu_explicit_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_for_lu_explicit_def
    JOIN establishment_for_lu_explicit_source_columns sc ON sc.definition_id = establishment_for_lu_explicit_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_for_lu_explicit_def.target_id AND tc.column_name = sc.column_name
    RETURNING *
),

-- 5. Establishment without legal unit with time_context for current year
establishment_without_lu_target AS (
    SELECT * FROM public.import_target
    WHERE schema_name = 'public'
      AND table_name = 'import_establishment_era_without_legal_unit'
), establishment_without_lu_current_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        , time_context_ident
        )
    SELECT establishment_without_lu_target.id
        , 'establishment_without_lu_current_year'
        , 'Establishment without Legal Unit - Current Year'
        , 'Import standalone establishments with validity period set to current year'
        , 'r_year_curr'
    FROM establishment_without_lu_target
    RETURNING *
), establishment_without_lu_current_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_without_lu_current_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_without_lu_current_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_without_lu_current_def.target_id
    WHERE itc.column_name NOT IN ('valid_from', 'valid_to')
    RETURNING *
), establishment_without_lu_current_mappings AS (
    -- Map source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_without_lu_current_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_without_lu_current_def
    JOIN establishment_without_lu_current_source_columns sc ON sc.definition_id = establishment_without_lu_current_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_without_lu_current_def.target_id AND tc.column_name = sc.column_name

    UNION ALL

    -- Add default mappings for valid_from and valid_to
    SELECT establishment_without_lu_current_def.id, NULL, tc.id, NULL, 'default'::public.import_source_expression
    FROM establishment_without_lu_current_def
    JOIN public.import_target_column tc ON tc.target_id = establishment_without_lu_current_def.target_id
    WHERE tc.column_name IN ('valid_from', 'valid_to')
    RETURNING *
),

-- 6. Establishment without legal unit with explicit valid_from/valid_to
establishment_without_lu_explicit_def AS (
    INSERT INTO public.import_definition
        ( target_id
        , slug
        , name
        , note
        )
    SELECT establishment_without_lu_target.id
        , 'establishment_without_lu_explicit_dates'
        , 'Establishment without Legal Unit - Explicit Dates'
        , 'Import standalone establishments with explicit valid_from and valid_to columns'
    FROM establishment_without_lu_target
    RETURNING *
), establishment_without_lu_explicit_source_columns AS (
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT establishment_without_lu_explicit_def.id, itc.column_name, ROW_NUMBER() OVER (ORDER BY itc.id)
    FROM establishment_without_lu_explicit_def
    JOIN public.import_target_column itc ON itc.target_id = establishment_without_lu_explicit_def.target_id
    RETURNING *
), establishment_without_lu_explicit_mappings AS (
    -- Map all source columns to target columns with same name
    INSERT INTO public.import_mapping (definition_id, source_column_id, target_column_id, source_value, source_expression)
    SELECT establishment_without_lu_explicit_def.id, sc.id, tc.id, NULL, NULL
    FROM establishment_without_lu_explicit_def
    JOIN establishment_without_lu_explicit_source_columns sc ON sc.definition_id = establishment_without_lu_explicit_def.id
    JOIN public.import_target_column tc ON tc.target_id = establishment_without_lu_explicit_def.target_id AND tc.column_name = sc.column_name
    RETURNING *
)
SELECT 1;

-- Set all import definitions to non-draft mode
UPDATE public.import_definition
SET draft = false
WHERE draft
RETURNING *;

END;
