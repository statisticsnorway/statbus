BEGIN;

--------------------------------------------------------------------------------
-- Sequence and function for stable identifiers
--------------------------------------------------------------------------------

CREATE SEQUENCE public.power_group_ident_seq;

CREATE FUNCTION public.generate_power_ident()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $generate_power_ident$
DECLARE
    _seq_val bigint;
    _chars text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    _base integer := 36;
    _result text := '';
BEGIN
    _seq_val := nextval('public.power_group_ident_seq');
    
    WHILE _seq_val > 0 LOOP
        _result := substr(_chars, (_seq_val % _base)::integer + 1, 1) || _result;
        _seq_val := _seq_val / _base;
    END LOOP;
    
    _result := lpad(COALESCE(NULLIF(_result, ''), '0'), 4, '0');
    RETURN 'PG' || _result;
END;
$generate_power_ident$;

COMMENT ON FUNCTION public.generate_power_ident() IS 
    'Generates stable, human-friendly identifiers for power groups (e.g., PG0001, PGABCD)';

--------------------------------------------------------------------------------
-- Power group table (NON-temporal, like enterprise)
-- Represents a control hierarchy - a derived/statistical artifact
-- Legal units link TO this table (like they link to enterprise)
--------------------------------------------------------------------------------

CREATE TABLE public.power_group (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    
    -- Stable identifier (auto-generated, never changes once assigned)
    ident text UNIQUE NOT NULL DEFAULT public.generate_power_ident(),
    
    -- Override fields for display (NULL = derive from root legal_unit)
    short_name varchar(16),
    name varchar(256),
    
    -- Type classification (domestic/foreign, national/multinational)
    type_id integer REFERENCES public.power_group_type(id),
    
    -- Optional metadata fields
    contact_person text,
    unit_size_id integer REFERENCES public.unit_size(id),
    data_source_id integer REFERENCES public.data_source(id),
    foreign_participation_id integer REFERENCES public.foreign_participation(id),
    
    -- Standard edit fields
    edit_comment varchar(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

-- NOTE: No valid_range, valid_from, valid_to - this is a TIMELESS table (like enterprise)
-- NOTE: No "active" column - active status is derived at query time from legal_relationship.valid_range
-- NOTE: No depth, width, reach columns - these are derived in views

-- Indexes
CREATE INDEX ix_power_group_type_id ON public.power_group USING btree (type_id);
CREATE INDEX ix_power_group_data_source_id ON public.power_group USING btree (data_source_id);
CREATE INDEX ix_power_group_unit_size_id ON public.power_group USING btree (unit_size_id);
CREATE INDEX ix_power_group_foreign_participation_id ON public.power_group USING btree (foreign_participation_id);
CREATE INDEX ix_power_group_name ON public.power_group USING btree (name);
CREATE INDEX ix_power_group_edit_by_user_id ON public.power_group USING btree (edit_by_user_id);

-- Comments
COMMENT ON TABLE public.power_group IS 'Represents a control hierarchy of legal units. TIMELESS registry - once created, exists forever. Active status derived from legal_relationship.valid_range at query time.';
COMMENT ON COLUMN public.power_group.ident IS 'Stable identifier (e.g., PG0001) that persists across hierarchy changes';

-- Helper function for FK validation (used by external_ident, tag_for_unit, unit_notes)
CREATE FUNCTION admin.power_group_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.power_group WHERE id = fk_id);
$$;

-- Enable RLS (required by 20240603 migration check)
ALTER TABLE public.power_group ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- Power group root status enum
--------------------------------------------------------------------------------

CREATE TYPE public.power_group_root_status AS ENUM ('single', 'cycle', 'multi');

COMMENT ON TYPE public.power_group_root_status IS
    'Status of a power group root: single (natural root), cycle (root chosen from cycle), multi (multiple roots merged)';

--------------------------------------------------------------------------------
-- Power root table (derived, refreshed by derive_power_groups)
-- Tracks the root legal unit and status per power group per time period
--------------------------------------------------------------------------------

CREATE TABLE public.power_root (
    power_group_id integer NOT NULL REFERENCES public.power_group(id) ON DELETE CASCADE,
    root_legal_unit_id integer NOT NULL,
    root_status public.power_group_root_status NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    valid_until date NOT NULL,
    PRIMARY KEY (power_group_id, valid_from)
);

CREATE INDEX ix_power_root_root_legal_unit_id ON public.power_root USING btree (root_legal_unit_id);
CREATE INDEX ix_power_root_valid ON public.power_root USING btree (valid_from, valid_until);

COMMENT ON TABLE public.power_root IS
    'Derived table tracking the root legal unit and root status per power group per time period. Refreshed by derive_power_groups.';
COMMENT ON COLUMN public.power_root.root_status IS
    'single: natural single root; cycle: root chosen from a cyclic component; multi: multiple natural roots merged';

-- Enable RLS (required by 20240603 migration check)
ALTER TABLE public.power_root ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- Power override table (NSO overrides, sql_saga temporal)
-- Allows NSO to override the automatically-chosen root for cycle/multi groups
--------------------------------------------------------------------------------

CREATE TABLE public.power_override (
    id integer GENERATED BY DEFAULT AS IDENTITY,
    power_group_id integer NOT NULL REFERENCES public.power_group(id) ON DELETE CASCADE,
    root_type public.power_group_root_status NOT NULL,
    custom_root_legal_unit_id integer NOT NULL,
    valid_range daterange NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    valid_until date,
    edit_comment varchar(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    CONSTRAINT power_override_root_type_check CHECK (root_type IN ('cycle', 'multi'))
);

CREATE INDEX ix_power_override_power_group_id ON public.power_override USING btree (power_group_id);
CREATE INDEX ix_power_override_valid_range ON public.power_override USING gist (valid_range);

COMMENT ON TABLE public.power_override IS
    'NSO overrides for power group root selection. Only applicable to cycle or multi-root groups.';
COMMENT ON COLUMN public.power_override.root_type IS
    'Must be cycle or multi — single-root groups have unambiguous natural roots';
COMMENT ON COLUMN public.power_override.custom_root_legal_unit_id IS
    'The legal unit ID the NSO designates as root for this power group during the valid period';

-- sql_saga temporal setup for power_override
SELECT sql_saga.add_era('public.power_override', 'valid_range', 'valid',
    ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at']);

SELECT sql_saga.add_unique_key(
    table_oid => 'public.power_override', key_type => 'primary',
    column_names => ARRAY['id'], unique_key_name => 'power_override_id_valid');

SELECT sql_saga.add_unique_key(
    table_oid => 'public.power_override', key_type => 'natural',
    column_names => ARRAY['power_group_id'],
    unique_key_name => 'power_override_power_group_valid');

SELECT sql_saga.add_for_portion_of_view('public.power_override');

-- Enable RLS (required by 20240603 migration check)
ALTER TABLE public.power_override ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- Trigger: When power_override changes, enqueue derive_power_groups
--------------------------------------------------------------------------------

CREATE FUNCTION public.power_override_queue_derive()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $power_override_queue_derive$
BEGIN
    PERFORM worker.enqueue_derive_power_groups();
    RETURN NULL;
END;
$power_override_queue_derive$;

CREATE TRIGGER power_override_derive_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.power_override
FOR EACH STATEMENT
EXECUTE FUNCTION public.power_override_queue_derive();

END;
