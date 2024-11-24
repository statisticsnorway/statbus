BEGIN;

CREATE TABLE public.activity_category (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    path public.ltree NOT NULL,
    parent_id integer REFERENCES public.activity_category(id) ON DELETE RESTRICT,
    level int GENERATED ALWAYS AS (public.nlevel(path)) STORED,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar NOT NULL,
    name character varying(256) NOT NULL,
    description text,
    active boolean NOT NULL,
    custom bool NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(standard_id, path, active)
);
CREATE INDEX ix_activity_category_parent_id ON public.activity_category USING btree (parent_id);

-- Trigger function to handle path updates, derive code, and lookup parent
CREATE FUNCTION public.lookup_parent_and_derive_code() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    code_pattern_var public.activity_category_code_behaviour;
    derived_code varchar;
    parent_path public.ltree;
BEGIN
    -- Look up the code pattern
    SELECT code_pattern INTO code_pattern_var
    FROM public.activity_category_standard
    WHERE id = NEW.standard_id;

    -- Derive the code based on the code pattern using CASE expression
    CASE code_pattern_var
        WHEN 'digits' THEN
            derived_code := regexp_replace(NEW.path::text, '[^0-9]', '', 'g');
        WHEN 'dot_after_two_digits' THEN
            derived_code := regexp_replace(regexp_replace(NEW.path::text, '[^0-9]', '', 'g'), '^([0-9]{2})(.+)$', '\1.\2');
        ELSE
            RAISE EXCEPTION 'Unknown code pattern: %', code_pattern_var;
    END CASE;

    -- Set the derived code
    NEW.code := derived_code;

    -- Ensure parent_id is consistent with the path
    -- Only update parent_id if path has parent segments
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO NEW.parent_id
        FROM public.activity_category
        WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
          AND active
        ;
    ELSE
        NEW.parent_id := NULL; -- No parent, set parent_id to NULL
    END IF;

    RETURN NEW;
END;
$$;

-- Trigger to call the function before insert or update
CREATE TRIGGER lookup_parent_and_derive_code_before_insert_update
BEFORE INSERT OR UPDATE ON public.activity_category
FOR EACH ROW
EXECUTE FUNCTION public.lookup_parent_and_derive_code();

END;
