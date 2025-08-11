BEGIN;

CREATE TYPE public.stat_type AS ENUM(
  'int',
  'float',
  'string',
  'bool'
);
--
CREATE TYPE public.stat_frequency AS ENUM(
  'daily',
  'weekly',
  'biweekly',
  'monthly',
  'bimonthly',
  'quarterly',
  'semesterly',
  'yearly'
);
--
CREATE TABLE public.stat_definition(
  id serial PRIMARY KEY,
  code varchar NOT NULL UNIQUE,
  type public.stat_type NOT NULL,
  frequency public.stat_frequency NOT NULL,
  name varchar NOT NULL,
  description text,
  priority integer UNIQUE,
  archived boolean NOT NULL DEFAULT false
);
--
CREATE INDEX ix_stat_definition_type ON public.stat_definition USING btree (type);
--
COMMENT ON COLUMN public.stat_definition.priority IS 'UI ordering of the entry fields';
COMMENT ON COLUMN public.stat_definition.archived IS 'At the time of data entry, only non archived codes can be used.';
--
CREATE VIEW public.stat_definition_ordered AS
    SELECT *
    FROM public.stat_definition
    ORDER BY priority ASC NULLS LAST, code
;

CREATE VIEW public.stat_definition_active AS
    SELECT *
    FROM public.stat_definition_ordered
    WHERE NOT archived
;

END;
