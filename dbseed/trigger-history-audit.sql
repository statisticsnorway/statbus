BEGIN;
--
--
CREATE TABLE legal_unit(
  id serial PRIMARY KEY,
  name text,
  employees integer,
  change_description varchar NOT NULL,
  valid_from date DEFAULT CURRENT_DATE NOT NULL,
  valid_to date DEFAULT 'infinity' ::date NOT NULL,
  active boolean GENERATED ALWAYS AS (valid_to IS NULL) STORED,
  updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
  CONSTRAINT valid_to_from_in_timely_order CHECK (valid_from <= valid_to OR valid_to IS NULL)
);
--
COMMENT ON COLUMN legal_unit.updated_at IS 'Use the statement_timestamp() as default, to allow known time to progress within a transaction, required due to exclusion constraint.';
COMMENT ON COLUMN legal_unit.valid_to IS 'Use the ''infinity'' as default, to prevent the exclusion constraint from failing when it is NULL';
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
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE legal_unit_history(
  id serial PRIMARY KEY,
  legal_unit_id integer REFERENCES legal_unit(id) ON DELETE SET NULL,
  name text,
  employees integer,
  valid_from date NOT NULL,
  valid_to date NOT NULL,
  change_description varchar,
  CONSTRAINT valid_to_from_in_timely_order CHECK (valid_from <= valid_to),
  CONSTRAINT no_valid_time_overlap
  EXCLUDE USING gist(legal_unit_id WITH =, daterange(valid_from, valid_to, '[]'
) WITH &&), CONSTRAINT one_entry_per_day_per_unit UNIQUE (legal_unit_id, valid_from)
);
CREATE INDEX legal_unit_history_legal_unit_id_idx ON legal_unit_history(legal_unit_id)
WHERE
  legal_unit_id IS NOT NULL;
--
CREATE INDEX legal_unit_history_valid_idx ON legal_unit_history(valid_from, valid_to);
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
--
-- AFTER INSERT Trigger
CREATE OR REPLACE FUNCTION legal_unit_after_insert()
  RETURNS TRIGGER
  AS $$
BEGIN
  -- Log or update legal_unit_history
  INSERT INTO legal_unit_history(legal_unit_id, name, employees, valid_from, valid_to, change_description)
    VALUES(NEW.id, NEW.name, NEW.employees, NEW.valid_from, NEW.valid_to, NEW.change_description)
  ON CONFLICT(legal_unit_id, valid_from)
    DO UPDATE SET
      valid_to = EXCLUDED.valid_to, name = EXCLUDED.name, employees = EXCLUDED.employees, change_description = EXCLUDED.change_description;
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
BEGIN
  -- Insert a new entry or update an existing one for today in legal_unit_history
  INSERT INTO legal_unit_history(legal_unit_id, name, employees, valid_from, valid_to, change_description)
    VALUES(NEW.id, NEW.name, NEW.employees, NEW.valid_from, NEW.valid_to, NEW.change_description)
  ON CONFLICT(legal_unit_id, valid_from)
    DO UPDATE SET
      valid_to = EXCLUDED.valid_to, name = EXCLUDED.name, employees = EXCLUDED.employees, change_description = EXCLUDED.change_description;
  -- If the new entry's valid_from date is different from the old one, then update the valid_to of the previous one
  IF NEW.valid_from <> OLD.valid_from THEN
    UPDATE
      legal_unit_history
    SET
      valid_to = NEW.valid_from - '1 day'::interval
    WHERE
      legal_unit_id = OLD.id
      AND valid_to IS NULL;
  END IF;
  -- End the known_to for the previous audit.
  WITH previous_audit AS(
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
    VALUES(NEW.id, to_jsonb(NEW), NEW.updated_at, 'infinity'::timestamptz, 'UPDATE');
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
-- AFTER DELETE Trigger
CREATE OR REPLACE FUNCTION legal_unit_before_delete()
  RETURNS TRIGGER
  AS $$
BEGIN
  -- Only allow delete if the valid_to was previously set to a sensible value
  -- thereby capturing the intent to delete.
  IF OLD.valid_to = 'infinity'::date THEN
    RAISE EXCEPTION 'Cannot delete a record with valid_to set to infinity';
  END IF;
  -- Log to legal_unit_audit
  INSERT INTO legal_unit_audit(legal_unit_id, record, known_from, known_to, op)
  -- There is no foreign key, after a delete
    VALUES(NULL, to_jsonb(OLD), OLD.updated_at, statement_timestamp(), 'DELETE');
  RETURN NULL;
END;
$$
LANGUAGE plpgsql;
--
CREATE TRIGGER legal_unit_before_delete
  AFTER DELETE ON legal_unit
  FOR EACH ROW
  EXECUTE FUNCTION legal_unit_before_delete();
--
--
\x
SELECT
  '########## Basic insert, update, delete' AS doc;
--
SELECT
  'Status from start of the year, regardless of when we knew.' AS doc;
SELECT
  *
FROM
  legal_unit_history
WHERE
--valid_from <= '2023-01-01' AND '2023-01-01' <= valid_to;
'2023-01-01' BETWEEN valid_from AND valid_to;
--
--
SELECT
  'Insert a legal unit' AS doc;
INSERT INTO legal_unit(name, employees, change_description)
  VALUES ('Anne', 1, 'UI Change');
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
  change_description = 'Manual editing',
  updated_at = statement_timestamp()
WHERE
  id = 1;
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
  valid_to = CURRENT_DATE,
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
  'Show a legal unit audit after delete' AS doc;

SELECT
  *
FROM
  legal_unit_audit;

--
--
SELECT
  '########## Adjusted time insert, update, delete' AS doc;

--
--
SELECT
  'Insert a legal unit' AS doc;

INSERT INTO legal_unit(name, employees, change_description, valid_from)
  VALUES ('Joe', 2, 'BRREG Import', '2022-06-01');

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
  change_description = 'BRREG Batch Upload',
  valid_from = '2022-09-01',
  updated_at = statement_timestamp()
WHERE
  name = 'Joe';

UPDATE
  legal_unit
SET
  change_description = 'Tax report',
  employees = 8,
  valid_from = '2022-10-01',
  updated_at = statement_timestamp()
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
--valid_from <= '2023-01-01' AND '2023-01-01' <= valid_to;
'2023-01-01' BETWEEN valid_from AND valid_to;

--
--
SELECT
  '########## Rewrite past insert, update, delete' AS doc;

--
--
SELECT
  'Insert a legal unit' AS doc;

INSERT INTO legal_unit(name, employees, change_description, valid_from, updated_at)
  VALUES ('Coop', 99, 'BRREG Import', '2022-03-01', now() - '1 year'::interval);

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
  employees = 198,
  valid_from = '2022-10-01',
  updated_at = now() - '6 months'::interval
WHERE
  name = 'Coop';

--
UPDATE
  legal_unit
SET
  change_description = 'Survey result',
  employees = 146,
  valid_from = '2022-08-01',
  valid_to = '2022-11-01',
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
  valid_to = '2023-01-01',
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
--valid_from <= '2023-01-01' AND '2023-01-01' <= valid_to;
'2023-01-01' BETWEEN valid_from AND valid_to;

--
--
\x
--
--
DROP TABLE legal_unit_history;

DROP TABLE legal_unit_audit;

DROP TABLE legal_unit;

DROP TYPE audit_operation;

DROP EXTENSION btree_gist;

END;

