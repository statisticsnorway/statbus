BEGIN;
--
CREATE EXTENSION IF NOT EXISTS btree_gist;
--
--

CREATE TABLE activity_category (
  id serial PRIMARY KEY,
  code varchar NOT NULL UNIQUE,
  name text,
  description text
);

INSERT INTO activity_category(code) VALUES ('A'),('B'),('C');

CREATE TABLE legal_unit(
  id serial PRIMARY KEY,
  unit_ident varchar UNIQUE NOT NULL,
  name text,
  stats JSONB NOT NULL,
  change_description varchar NOT NULL,
  valid_from date DEFAULT CURRENT_DATE NOT NULL,
  valid_to date DEFAULT 'infinity' ::date NOT NULL,
  enabled boolean GENERATED ALWAYS AS (valid_to = 'infinity'::date) STORED,
  updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
  CONSTRAINT valid_to_from_in_timely_order CHECK (valid_from <= valid_to)
);
--
COMMENT ON COLUMN legal_unit.updated_at IS 'Use the statement_timestamp() as default, to allow known time to progress within a transaction, required due to exclusion constraint.';
COMMENT ON COLUMN legal_unit.valid_to IS 'Use the ''infinity'' as default, to prevent the exclusion constraint from failing when it is NULL. This will be translated to max target system supported value in reports.';
--
--
CREATE TABLE activity(
  id serial PRIMARY KEY,
  legal_unit_id integer REFERENCES legal_unit(id) ON DELETE CASCADE,
  activity_category_id integer REFERENCES activity_category(id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  UNIQUE(legal_unit_id, activity_category_id)
);

CREATE VIEW view_legal_unit_activity AS
  SELECT lu.unit_ident, lu.name AS legal_unit_name, ac.code AS activity_code, ac.name AS activity_name
  FROM legal_unit AS lu
  JOIN activity AS lua ON lua.legal_unit_id = lu.id
  JOIN activity_category AS ac ON lua.activity_category_id = ac.id;
--
-- Create a function to handle the bulk upserts
CREATE OR REPLACE FUNCTION upsert_legal_unit_activity()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert or update activities based on the upload
    INSERT INTO activity (legal_unit_id, activity_category_id, updated_at)
    SELECT lu.id, ac.id, statement_timestamp()
    FROM legal_unit lu
    JOIN activity_category ac ON ac.code = NEW.activity_code
    WHERE lu.unit_ident = NEW.unit_ident
    ON CONFLICT (legal_unit_id, activity_category_id)
    DO UPDATE SET updated_at = statement_timestamp();

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the "INSTEAD OF INSERT" trigger on the view
CREATE TRIGGER upsert_legal_unit_activity
INSTEAD OF INSERT ON view_legal_unit_activity
FOR EACH ROW
EXECUTE FUNCTION upsert_legal_unit_activity();

CREATE OR REPLACE FUNCTION delete_stale_legal_unit_activity()
RETURNS TRIGGER AS $$
BEGIN
    -- All the `legal_unit_id` with a recent update must be complete.
    WITH changed_legal_unit AS (
      SELECT DISTINCT legal_unit_id
      FROM activity
      WHERE updated_at = statement_timestamp()
    )
    -- Delete activities that have a stale updated_at
    DELETE FROM activity
    WHERE legal_unit_id IN (SELECT legal_unit_id FROM changed_legal_unit)
    AND updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER delete_stale_legal_unit_activity
AFTER INSERT ON view_legal_unit_activity
FOR EACH STATEMENT
EXECUTE FUNCTION delete_stale_legal_unit_activity();

--
-- Prevent primary key changes
CREATE OR REPLACE FUNCTION prevent_legal_unit_id_update()
  RETURNS TRIGGER
  AS $$
BEGIN
  IF NEW.id <> OLD.id THEN
    RAISE EXCEPTION 'Update of id column in legal_unit table is not allowed!';
  END IF;
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER trigger_prevent_legal_unit_id_update
  BEFORE UPDATE OF id ON legal_unit
  FOR EACH ROW
  EXECUTE FUNCTION prevent_legal_unit_id_update();
--
--
CREATE TYPE stat_type AS ENUM(
  'int',
  'float',
  'string',
  'bool'
);
--
CREATE TYPE stat_frequency AS ENUM(
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
CREATE TABLE stat_definition(
  id serial PRIMARY KEY,
  code varchar NOT NULL UNIQUE,
  type stat_type NOT NULL,
  frequency stat_frequency NOT NULL,
  name varchar NOT NULL,
  description text,
  priority integer UNIQUE,
  enabled boolean NOT NULL DEFAULT true
);
--
COMMENT ON COLUMN stat_definition.priority IS 'UI ordering of the entry fields';
COMMENT ON COLUMN stat_definition.enabled IS 'At the time of data entry, only enabled codes can be used.';
--
INSERT INTO stat_definition(code, type, frequency, name, description, priority) VALUES
  ('employees','int','monthly','Number of people employed','The number of people receiving an official salary with government reporting.',2),
  ('verified','bool','yearly','Verified','That an employee as had phone contact with and found in the tax registry.',1),
  ('turnover','int','yearly','Turnover','The amount (EUR)',3);
--
--
CREATE TABLE legal_unit_history(
  id serial PRIMARY KEY,
  legal_unit_id integer REFERENCES legal_unit(id) ON DELETE SET NULL,
  unit_ident varchar NOT NULL,
  name text,
  stats JSONB NOT NULL,
  valid_from date NOT NULL,
  valid_to date NOT NULL,
  change_description varchar,
  CONSTRAINT valid_to_from_in_timely_order CHECK (valid_from <= valid_to),
  CONSTRAINT history_no_valid_time_overlap
  EXCLUDE USING gist(legal_unit_id WITH =, daterange(valid_from, valid_to, '[]'
) WITH &&), CONSTRAINT history_one_entry_per_day_per_unit UNIQUE (legal_unit_id, valid_from)
);
COMMENT ON TABLE legal_unit_history IS 'A historical record of data, kept even in the case of delete.';
CREATE INDEX legal_unit_history_legal_unit_id_idx ON legal_unit_history(legal_unit_id)
WHERE
  legal_unit_id IS NOT NULL;
--
--
CREATE UNIQUE INDEX legal_unit_history_legal_unit_id_valid_to_infinity_key ON legal_unit_history(legal_unit_id, valid_to) WHERE valid_to = 'infinity'::date;

--
CREATE INDEX legal_unit_history_valid_idx ON legal_unit_history(valid_from, valid_to);
--
--
CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view()
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    dyn_query TEXT;
    stat_code RECORD;
BEGIN
    -- Start building the dynamic query
    dyn_query := 'CREATE OR REPLACE VIEW legal_unit_history_with_stats AS SELECT id, unit_ident, name, change_description, valid_from, valid_to';

    -- For each code in stat_definition, add it as a column
    FOR stat_code IN (SELECT code FROM stat_definition WHERE enabled = true ORDER BY priority)
    LOOP
        dyn_query := dyn_query || ', stats ->> ''' || stat_code.code || ''' AS "' || stat_code.code || '"';
    END LOOP;

    dyn_query := dyn_query || ' FROM legal_unit_history';

    -- Execute the dynamic query
    EXECUTE dyn_query;
    -- Reload PostgREST to expose the new view
    NOTIFY pgrst, 'reload config';
END;
$$;
--
CREATE OR REPLACE FUNCTION generate_legal_unit_history_with_stats_view_trigger()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    -- Call the view generation function
    PERFORM generate_legal_unit_history_with_stats_view();

    -- As this is an AFTER trigger, we don't need to return any specific row.
    RETURN NULL;
END;
$$;
--
CREATE TRIGGER regenerate_stats_view_trigger
AFTER INSERT OR UPDATE OR DELETE ON stat_definition
FOR EACH ROW
EXECUTE FUNCTION generate_legal_unit_history_with_stats_view_trigger();
--
SELECT generate_legal_unit_history_with_stats_view();
--
--
CREATE TYPE audit_operation AS ENUM(
  'INSERT',
  'UPDATE',
  'DELETE'
);
--
CREATE TABLE legal_unit_audit(
  id serial PRIMARY KEY,
  op audit_operation NOT NULL,
  op_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
  legal_unit_id integer REFERENCES legal_unit(id) ON DELETE SET NULL ON UPDATE CASCADE,
  record jsonb NOT NULL,
  known_from timestamp with time zone NOT NULL,
  known_to timestamp with time zone NOT NULL,
  CONSTRAINT known_to_from_in_timely_order CHECK (known_from <= known_to),
  CONSTRAINT no_known_time_overlap
  EXCLUDE USING gist(legal_unit_id WITH =, tstzrange(known_from, known_to, '[)'
) WITH &&)
);
--
COMMENT ON TABLE legal_unit_audit IS 'A record of all changes, kept even in the case of delete.';
--
CREATE UNIQUE INDEX legal_unit_audit_legal_unit_id_known_to_infinity_key ON legal_unit_audit(legal_unit_id, known_to) WHERE known_to = 'infinity'::timestamptz;
--
--
-- Trigger function
CREATE OR REPLACE FUNCTION legal_unit_audit_op_at_consistency()
  RETURNS TRIGGER
  AS $$
BEGIN
  -- If it's an INSERT operation, set the value of op_at
  IF TG_OP = 'INSERT' THEN
    NEW.op_at := statement_timestamp();
    RETURN NEW;
  END IF;

  -- If it's an UPDATE operation, check if the op_at is being changed
  IF TG_OP = 'UPDATE' THEN
    IF NEW.op_at <> OLD.op_at THEN
      RAISE EXCEPTION 'Cannot change op_at';
    END IF;
    RETURN NEW;
  END IF;

  -- Default return for other operations
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- Before trigger for INSERT or UPDATE
CREATE TRIGGER legal_unit_audit_op_at_consistency
  BEFORE INSERT OR UPDATE ON legal_unit_audit
  FOR EACH ROW
  EXECUTE FUNCTION legal_unit_audit_op_at_consistency();
--
--
CREATE OR REPLACE FUNCTION check_legal_unit_stats_validity()
RETURNS TRIGGER AS $$
DECLARE
    valid_codes TEXT[];
    stat_keys TEXT[];
    invalid_keys TEXT[];
    missing_keys TEXT[];
BEGIN
    -- Fetch valid codes from stat_definition where they are enabled
    SELECT ARRAY_AGG(code) INTO valid_codes
    FROM stat_definition
    WHERE enabled IS TRUE;

    -- Extract all the keys from the stats JSONB column
    SELECT ARRAY_AGG(jsonb_object_keys) INTO stat_keys
    FROM jsonb_object_keys(NEW.stats);

    -- Identify any invalid keys
    invalid_keys := ARRAY(
        SELECT unnest(stat_keys)
        EXCEPT
        SELECT unnest(valid_codes)
    );

    -- Identify any missing keys
    missing_keys := ARRAY(
        SELECT unnest(valid_codes)
        EXCEPT
        SELECT unnest(stat_keys)
    );

    -- If there are any invalid or missing keys, raise an exception with those keys listed
    IF array_length(invalid_keys, 1) > 0 OR array_length(missing_keys, 1) > 0 THEN
        RAISE EXCEPTION 'stats has invalid keys: %, and missing keys: %',
            to_json(invalid_keys),
            to_json(missing_keys);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
CREATE TRIGGER check_legal_unit_stats_validity
BEFORE INSERT OR UPDATE OF stats ON legal_unit
FOR EACH ROW EXECUTE FUNCTION check_legal_unit_stats_validity();
--
--
CREATE OR REPLACE FUNCTION ensure_legal_unit_updated_at_increments()
RETURNS TRIGGER AS $$
BEGIN
  -- If the updated_at timestamp hasn't changed, set it to the current timestamp
  IF OLD.updated_at = NEW.updated_at THEN
    NEW.updated_at := statement_timestamp();
  END IF;
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER ensure_legal_unit_updated_at_increments
BEFORE UPDATE ON legal_unit
FOR EACH ROW
EXECUTE FUNCTION ensure_legal_unit_updated_at_increments();

--
--
-- AFTER INSERT Trigger
CREATE OR REPLACE FUNCTION legal_unit_after_insert()
  RETURNS TRIGGER
  AS $$
BEGIN
  -- Log to legal_unit_history
  INSERT INTO legal_unit_history(legal_unit_id, unit_ident, name, stats, valid_from, valid_to, change_description)
    VALUES(NEW.id, NEW.unit_ident, NEW.name, NEW.stats, NEW.valid_from, NEW.valid_to, NEW.change_description);
  -- Log to legal_unit_audit
  INSERT INTO legal_unit_audit(legal_unit_id, record, known_from, known_to, op)
    VALUES(NEW.id, to_jsonb(NEW), NEW.updated_at, 'infinity'::timestamptz, 'INSERT');
  RETURN NULL;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER legal_unit_after_insert
  AFTER INSERT ON legal_unit
  FOR EACH ROW
  EXECUTE FUNCTION legal_unit_after_insert();
--
-- AFTER UPDATE Trigger
CREATE OR REPLACE FUNCTION legal_unit_after_update()
  RETURNS TRIGGER
  AS $$
DECLARE
  c RECORD;
  adjusted_valid_from date;
  adjusted_valid_to date;
BEGIN
  -- Loop through each conflicting row
  RAISE DEBUG 'NEW row %', to_json(NEW.*);
  FOR c IN
  SELECT
    id,
    valid_from,
    valid_to
  FROM
    legal_unit_history
  WHERE
    legal_unit_id = NEW.id
    AND daterange(valid_from, valid_to, '[]') && daterange(NEW.valid_from, NEW.valid_to, '[]')
  ORDER BY
    valid_from LOOP
      RAISE DEBUG 'Conflicting row %', to_json(c.*);
      -- Scenario #1: n.valid_from < c.valid_to AND c.valid_to <= n.valid_to
      -- c      ------------]
      -- n           [-------------------------]
      -- Resolution: c.valid_to = n.valid_from - '1 day'
      -- c      ----]
      -- n           [-------------------------]
      --
      IF NEW.valid_from <= c.valid_to AND c.valid_to <= NEW.valid_to THEN
        RAISE DEBUG 'Scenario #1: NEW.valid_from <= c.valid_to AND c.valid_to <= NEW.valid_to';
        adjusted_valid_to := NEW.valid_from - interval '1 day';
        RAISE DEBUG 'adjusted_valid_to = %', adjusted_valid_to;
        IF adjusted_valid_to < c.valid_from THEN
          RAISE DEBUG 'Deleting conflict with zero valid duration';
          DELETE FROM legal_unit_history
          WHERE id = c.id;
        ELSE
          RAISE DEBUG 'Adjusting conflicting row';
          UPDATE
            legal_unit_history
          SET
            valid_to = adjusted_valid_to
          WHERE
            id = c.id;
        END IF;
        -- Scenario #2: c.valid_from < n.valid_from AND n.valid_to <= c.valid_to
        -- c      -----------------------------------------]
        -- n           [-------------------------]
        -- Resolution: c.valid_to = n.valid_from - '1 day', c_new.valid_from = n.valid_to + '1 day', c_new.valid_to = c.valid_to
        -- c      ----]
        -- n           [-------------------------]
        -- c'                                    [---------
        --
      ELSIF c.valid_from <= NEW.valid_from
          AND NEW.valid_to <= c.valid_to THEN
          RAISE DEBUG 'Scenario #2: c.valid_from <= NEW.valid_from AND NEW.valid_to <= c.valid_to';
        adjusted_valid_from := NEW.valid_to + interval '1 day';
        adjusted_valid_to := NEW.valid_from - interval '1 day';
        RAISE DEBUG 'adjusted_valid_from = %', adjusted_valid_from;
        RAISE DEBUG 'adjusted_valid_to = %', adjusted_valid_to;
        IF adjusted_valid_to < c.valid_from THEN
          RAISE DEBUG 'Deleting conflict with zero valid duration';
          DELETE FROM legal_unit_history
          WHERE id = c.id;
        ELSE
          RAISE DEBUG 'Adjusting conflicting row';
          UPDATE
            legal_unit_history
          SET
            valid_to = adjusted_valid_to
          WHERE
            id = c.id;
        END IF;
        IF c.valid_to < adjusted_valid_from THEN
          RAISE DEBUG 'Don''t create zero duration row';
        ELSIF NEW.enabled THEN
          RAISE DEBUG 'Inserting new tail';
          INSERT INTO legal_unit_history(legal_unit_id, name, stats, valid_from, valid_to, change_description)
            VALUES (NEW.id, adjusted_valid_from, c.name, c.stats, c.valid_from, c.valid_to, c.change_description);
        ELSE
          RAISE DEBUG 'No tail for a liquidated company';
        END IF;
        -- Scenario #3: n.valid_from < c.valid_from AND c.valid_to <= n.valid_to
        -- c             [-------------]
        -- n           [-------------------------]
        -- Resolution: delete c
        -- n           [-------------------------]
        --
      ELSIF NEW.valid_from <= c.valid_from
          AND c.valid_to <= NEW.valid_to THEN
          RAISE DEBUG 'Scenario #3: NEW.valid_from <= c.valid_from AND c.valid_to <= NEW.valid_to';
        RAISE DEBUG 'Deleting conflict contained by NEW';
        DELETE FROM legal_unit_history
        WHERE id = c.id;
        -- Scenario #4: n.valid_from < c.valid_from AND n.valid_to <= c.valid_to
        -- c                   [----------------------------]
        -- n           [-------------------------]
        -- Resolution: c.valid_from = n.valid_to + '1 day'
        -- c                                     [----------]
        -- n           [-------------------------]
        --
      ELSIF NEW.valid_from <= c.valid_from
          AND NEW.valid_to <= c.valid_to THEN
          RAISE DEBUG 'Scenario #4: NEW.valid_from <= c.valid_from AND NEW.valid_to <= c.valid_to';
        adjusted_valid_from := NEW.valid_to + interval '1 day';
        RAISE DEBUG 'adjusted_valid_from = %', adjusted_valid_from;
        IF c.valid_to < adjusted_valid_from THEN
          RAISE DEBUG 'Deleting conflict with zero valid duration';
          DELETE FROM legal_unit_history
          WHERE id = c.id;
        ELSIF NOT NEW.enabled THEN
          RAISE DEBUG 'Deleting conflict after liquidation';
          DELETE FROM legal_unit_history
          WHERE id = c.id;
        ELSE
          RAISE DEBUG 'Adjusting conflicting row';
          UPDATE
            legal_unit_history
          SET
            valid_from = adjusted_valid_from
          WHERE
            id = c.id;
        END IF;
      ELSE
        RAISE EXCEPTION 'Unhandled conflicting case';
      END IF;
    END LOOP;
  --
  -- Insert a new entry or update an existing one for today in legal_unit_history
  RAISE DEBUG 'legal_unit_history(legal_unit_id=%, name=%, stats=%, valid_from=%, valid_to=%, change_description=%)', NEW.id, NEW.name, NEW.stats, NEW.valid_from, NEW.valid_to, NEW.change_description;
  INSERT INTO legal_unit_history(legal_unit_id, unit_ident, name, stats, valid_from, valid_to, change_description)
    VALUES (NEW.id, NEW.unit_ident, NEW.name, NEW.stats, NEW.valid_from, NEW.valid_to, NEW.change_description);
  -- End the known_to for the previous audit.
  WITH previous_audit AS (
    SELECT
      id
    FROM
      legal_unit_audit
    WHERE
      legal_unit_id = NEW.id
    ORDER BY
      known_from DESC
    LIMIT 1)
UPDATE
  legal_unit_audit
SET
  known_to = NEW.updated_at
FROM
  previous_audit
WHERE
  legal_unit_audit.id = previous_audit.id;
  --
  -- Log to legal_unit_audit
  INSERT INTO legal_unit_audit(legal_unit_id, record, known_from, known_to, op)
    VALUES (NEW.id, to_jsonb(NEW), NEW.updated_at, 'infinity'::timestamptz, 'UPDATE');
  RETURN NULL;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER legal_unit_after_update
  AFTER UPDATE ON legal_unit
  FOR EACH ROW
  EXECUTE FUNCTION legal_unit_after_update();
--
--
CREATE OR REPLACE FUNCTION legal_unit_before_delete()
  RETURNS TRIGGER AS $$
BEGIN
  -- Only allow delete if the valid_to was previously set to a sensible value
  -- thereby capturing the intent to delete.
  IF OLD.enabled THEN
    RAISE EXCEPTION 'Cannot delete a record while enabled. Requires valid_to to have a date';
  END IF;

  -- End the known_to for the previous audit.
  -- While there still is a foreign key available to lookup.
  WITH previous_audit AS (
    SELECT
      id
    FROM
      legal_unit_audit
    WHERE
      legal_unit_id = OLD.id
      AND known_to = 'infinity'::timestamptz
    LIMIT 1)
  UPDATE
    legal_unit_audit
  SET
    known_to = OLD.updated_at
  FROM
    previous_audit
  WHERE
    legal_unit_audit.id = previous_audit.id;

  RETURN OLD;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER legal_unit_before_delete
  BEFORE DELETE ON legal_unit
  FOR EACH ROW
  EXECUTE FUNCTION legal_unit_before_delete();
--
--
-- AFTER DELETE Trigger
CREATE OR REPLACE FUNCTION legal_unit_after_delete()
  RETURNS TRIGGER
  AS $$
BEGIN
  -- Log to legal_unit_audit
  INSERT INTO legal_unit_audit(legal_unit_id, record, known_from, known_to, op)
  -- There is no foreign key, after a delete
    VALUES(NULL, to_jsonb(OLD), OLD.updated_at, statement_timestamp(), 'DELETE');
  RETURN NULL;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER legal_unit_after_delete
  AFTER DELETE ON legal_unit
  FOR EACH ROW
  EXECUTE FUNCTION legal_unit_after_delete();
--
--
SET client_min_messages = debug;
\x
SELECT
  '########## Basic insert, update, delete' AS doc;
SAVEPOINT using_default;
--
SELECT
  'Status from start of the year, regardless of when we knew.' AS doc;
SELECT
  *
FROM
  legal_unit_history
WHERE
  -- We don't use the x BETWEEN y AND Z because PostgREST doesn't easily support it.
  valid_from <= '2023-01-01'
  AND '2023-01-01' <= valid_to;
--
--
SELECT
  'Insert a legal unit' AS doc;
INSERT INTO legal_unit(unit_ident, name, stats, change_description)
  VALUES ('23nd','Anne', '{"verified": true, "employees": 1, "turnover": null}', 'UI Change');
--
SELECT
  'Show a legal unit after insert' AS doc;
SELECT
  *
FROM
  legal_unit;
SELECT
  'Show a legal unit history after insert' AS doc;
SELECT
  *
FROM
  legal_unit_history;
SELECT
  'Show a legal unit audit after insert' AS doc;
SELECT
  *
FROM
  legal_unit_audit;
--
SELECT
  'Update a legal unit' AS doc;
UPDATE
  legal_unit
SET
  name = 'Eriks',
  stats = jsonb_set(stats, '{employees}', '2'::jsonb),
  change_description = 'Manual editing'
WHERE
  id = 1;
--
SELECT
  'Show a legal unit after update' AS doc;
SELECT
  *
FROM
  legal_unit;
--
SELECT
  'Show a legal unit history after update' AS doc;
SELECT
  *
FROM
  legal_unit_history;
--
SELECT
  'Show a legal unit audit after update' AS doc;
SELECT
  *
FROM
  legal_unit_audit;
--
--
SAVEPOINT before_invalid_delete;
--
SELECT
  'Delete a legal unit - without setting valid_to properly' AS doc;
DELETE FROM legal_unit
WHERE id = 1;
--
ROLLBACK TO SAVEPOINT before_invalid_delete;

--
SELECT
  'Delete a legal unit - after setting valid_to properly' AS doc;

UPDATE
  legal_unit
SET
  valid_to = valid_from,
  change_description = 'Mark the company as liquidated'
WHERE
  id = 1;

DELETE FROM legal_unit
WHERE id = 1;

--
SELECT
  'Show a legal unit after delete' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after delete' AS doc;

SELECT
  *
FROM
  legal_unit_history;

SELECT
  'Show a legal unit history with stats after delete' AS doc;

SELECT
  *
FROM
  legal_unit_history_with_stats;

SELECT
  'Show a legal unit audit after delete' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

ROLLBACK TO SAVEPOINT using_default;

--
--
SELECT
  '########## Adjusted time insert, update, delete' AS doc;

SAVEPOINT using_adjusted;

--
--
SELECT
  'Insert a legal unit' AS doc;

INSERT INTO legal_unit(unit_ident, name, stats, change_description, valid_from)
  VALUES ('87fm','Joe', '{"verified": false, "employees": 2, "turnover": null}', 'BRREG Import', '2022-06-01');

--
SELECT
  'Show a legal unit after insert' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after insert' AS doc;

SELECT
  *
FROM
  legal_unit_history;

SELECT
  'Show a legal unit audit after insert' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
SELECT
  'Update a legal unit' AS doc;

UPDATE
  legal_unit
SET
  name = 'Trader Joes',
  stats = jsonb_set(stats, '{verified}', 'true'::jsonb),
  change_description = 'BRREG Batch Upload',
  valid_from = '2022-09-01'
WHERE
  name = 'Joe';

UPDATE
  legal_unit
SET
  change_description = 'Tax report',
  stats = jsonb_set(stats, '{employees}', '8'::jsonb),
  valid_from = '2022-10-01'
WHERE
  name = 'Trader Joes';

--
SELECT
  'Show a legal unit after update' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after update' AS doc;

SELECT
  *
FROM
  legal_unit_history;

SELECT
  'Show a legal unit audit after update' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
--
SELECT
  'Delete a legal unit - after setting valid_to properly' AS doc;

UPDATE
  legal_unit
SET
  valid_to = '2022-12-31',
  change_description = 'Mark the company as liquidated'
WHERE
  name = 'Trader Joes';

DELETE FROM legal_unit
WHERE name = 'Trader Joes';

--
SELECT
  'Show a legal unit after delete' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after delete' AS doc;

SELECT
  *
FROM
  legal_unit_history;

SELECT
  'Show a legal unit audit after delete' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
--
--
SELECT
  'Status from end of the year' AS doc;

SELECT
  *
FROM
  legal_unit_history
WHERE
  -- We don't use the x BETWEEN y AND Z because PostgREST doesn't easily support it.
  valid_from <= '2022-12-31'
  AND '2022-12-31' <= valid_to;

--
ROLLBACK TO SAVEPOINT using_adjusted;

--
--
SELECT
  '########## Rewrite past insert, update, delete' AS doc;

SAVEPOINT rewrite_history;

--
--
SELECT
  'Insert a legal unit' AS doc;

INSERT INTO legal_unit(unit_ident, name, stats, change_description, valid_from, updated_at)
  VALUES ('754n3','Coop', '{"employees": 99, "turnover": null, "verified": null}', 'BRREG Import', '2022-03-01', now() - '1 year'::interval);

--
SELECT
  'Show a legal unit after insert' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after insert' AS doc;

SELECT
  *
FROM
  legal_unit_history;

SELECT
  'Show a legal unit audit after insert' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
SELECT
  'Update a legal unit' AS doc;

UPDATE
  legal_unit
SET
  change_description = 'Manual correction',
  valid_from = '2022-01-01',
  updated_at = now() - '9 months'::interval
WHERE
  name = 'Coop';

--
UPDATE
  legal_unit
SET
  change_description = 'Tax report',
  stats = jsonb_set(stats, '{employees}', '198'::jsonb),
  valid_from = '2022-10-01',
  updated_at = now() - '6 months'::interval
WHERE
  name = 'Coop';

--
UPDATE
  legal_unit
SET
  change_description = 'Survey result',
  stats = jsonb_set(stats, '{employees}', '146'::jsonb),
  valid_from = '2022-08-01',
  updated_at = now() - '3 months'::interval
WHERE
  name = 'Coop';

--
SELECT
  'Show a legal unit after update' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after update' AS doc;

SELECT
  *
FROM
  legal_unit_history
ORDER BY
  valid_from;

SELECT
  'Show a legal unit audit after update' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
--
SELECT
  'Delete a legal unit - after setting valid_to properly' AS doc;

UPDATE
  legal_unit
SET
  valid_to = '2023-01-01',
  change_description = 'Mark the company as liquidated'
WHERE
  name = 'Coop';

--
SELECT
  'Show a legal unit history after mark for delete' AS doc;

SELECT
  *
FROM
  legal_unit_history
ORDER BY
  valid_from;

--
DELETE FROM legal_unit
WHERE name = 'Coop';

--
SELECT
  'Show a legal unit after delete' AS doc;

SELECT
  *
FROM
  legal_unit;

SELECT
  'Show a legal unit history after delete' AS doc;

SELECT
  *
FROM
  legal_unit_history
ORDER BY
  valid_from;

SELECT
  'Show a legal unit audit after delete' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
--
--
SELECT
  'Status from end of the year' AS doc;

SELECT
  *
FROM
  legal_unit_history
WHERE
  -- We don't use the x BETWEEN y AND Z because PostgREST doesn't easily support it.
  valid_from <= '2022-12-31'
  AND '2022-12-31' <= valid_to
ORDER BY
  valid_from;
--
--
SELECT
  '########## Rewrite past insert, update, delete' AS doc;

SAVEPOINT rewrite_history;

--
--
SELECT
  'Insert a legal unit' AS doc;

INSERT INTO legal_unit(unit_ident, name, stats, change_description, valid_from)
  VALUES ('754n3','Coffe', '{"employees": 1, "turnover": null, "verified": null}', 'BRREG Import', '2023-01-01');

INSERT INTO view_legal_unit_activity(unit_ident, activity_code) VALUES
  ('754n3','A'), ('754n3','B'), ('754n3','C');

SELECT 'Show activity after upsert through view' AS doc;
SELECT * FROM activity;

INSERT INTO view_legal_unit_activity(unit_ident, activity_code) VALUES
  ('754n3','A'), ('754n3','B');

SELECT 'Show activity after upsert with delete through view' AS doc;
SELECT * FROM activity;

--
--
ROLLBACK TO SAVEPOINT rewrite_history;

--
--
\x
SET client_min_messages = INFO;

--
--
DROP VIEW legal_unit_history_with_stats;
DROP VIEW view_legal_unit_activity;

DROP TABLE activity;
DROP TABLE activity_category;

DROP TABLE legal_unit_history;

DROP TABLE legal_unit_audit;

DROP TABLE legal_unit;

DROP TABLE stat_definition;

DROP TYPE audit_operation;
DROP TYPE stat_type;
DROP TYPE stat_frequency;

DROP EXTENSION btree_gist;

END;

