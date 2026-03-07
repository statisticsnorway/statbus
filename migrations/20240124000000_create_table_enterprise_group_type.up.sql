BEGIN;

-- Classification of power groups (domestic/foreign controlled, national/multinational)
CREATE TABLE public.power_group_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    enabled boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_power_group_type_code ON public.power_group_type USING btree (code) WHERE enabled;
CREATE INDEX ix_power_group_type_enabled ON public.power_group_type USING btree (enabled);

COMMENT ON TABLE public.power_group_type IS 'Classification of power groups (domestic/foreign controlled, national/multinational)';

END;
