-- Migration 20250123124701: create table status
BEGIN;

CREATE TABLE public.status (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code varchar NOT NULL,
    name text NOT NULL,
    assigned_by_default BOOLEAN NOT NULL,
    include_unit_in_reports boolean NOT NULL,
    priority integer NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL DEFAULT false,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(code, active, custom)
);
CREATE UNIQUE INDEX ix_status_code ON public.foreign_participation USING btree (code) WHERE active;
CREATE INDEX ix_status_active ON public.status USING btree (active);
CREATE UNIQUE INDEX ix_status_only_one_assigned_by_default ON public.status USING btree (assigned_by_default) WHERE active AND assigned_by_default;

-- Insert default statuses
INSERT INTO public.status (code, name, include_unit_in_reports, assigned_by_default, priority, active, custom) VALUES
    ('active', 'Active', true, true, 1, true, false),
    ('passive', 'Passive', false, false, 2, true, false);

END;
