BEGIN;

\echo public.relative_period_code
CREATE TYPE public.relative_period_code AS ENUM (
    -- For data entry with context_valid_from and context_valid_to. context_valid_on should be context_valid_from when infinity, else context_valid_to
    'today',
    'year_curr',
    'year_prev',
    'year_curr_only',
    'year_prev_only',

    -- For data query with context_valid_on only, no context_valid_from and context_valid_to
    'start_of_week_curr',
    'stop_of_week_prev',
    'start_of_week_prev',

    'start_of_month_curr',
    'stop_of_month_prev',
    'start_of_month_prev',

    'start_of_quarter_curr',
    'stop_of_quarter_prev',
    'start_of_quarter_prev',

    'start_of_semester_curr',
    'stop_of_semester_prev',
    'start_of_semester_prev',

    'start_of_year_curr',
    'stop_of_year_prev',
    'start_of_year_prev',

    'start_of_quinquennial_curr',
    'stop_of_quinquennial_prev',
    'start_of_quinquennial_prev',

    'start_of_decade_curr',
    'stop_of_decade_prev',
    'start_of_decade_prev'
);

\echo public.relative_period_scope
CREATE TYPE public.relative_period_scope AS ENUM (
    'input_and_query',
    'query',
    'input'
);

\echo public.relative_period
CREATE TABLE public.relative_period (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code public.relative_period_code UNIQUE NOT NULL,
    name_when_query character varying(256),
    name_when_input character varying(256),
    scope public.relative_period_scope NOT NULL,
    active boolean NOT NULL DEFAULT true,
    CONSTRAINT "scope input_and_query requires name_when_input"
    CHECK (
        CASE scope
        WHEN 'input_and_query' THEN name_when_input IS NOT NULL AND name_when_query IS NOT NULL
        WHEN 'query'           THEN name_when_input IS     NULL AND name_when_query IS NOT NULL
        WHEN 'input'           THEN name_when_input IS NOT NULL AND name_when_query IS     NULL
        END
    )
);

END;