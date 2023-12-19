\set original_ECHO :ECHO
\set ECHO all

--
DROP TABLE IF EXISTS uk;
DROP TABLE IF EXISTS fk;
CREATE TABLE uk(id integer, s integer, e integer);
SELECT periods.add_period('uk', 'p', 's', 'e');
SELECT periods.add_unique_key('uk', ARRAY['id'], 'p');

CREATE TABLE fk(id integer, uk_id integer, s integer, e integer);
SELECT periods.add_period('fk', 'q', 's', 'e');
SELECT periods.add_unique_key('fk', ARRAY['id'], 'q');
SELECT periods.add_foreign_key('fk', ARRAY['uk_id'], 'q', 'uk_id_p');
--
TABLE periods.periods;
TABLE periods.foreign_keys;

--
INSERT INTO uk(id, s, e)        VALUES    (1, 1, 3),    (1, 3, 5);
INSERT INTO fk(id, uk_id, s, e) VALUES (1, 1, 1, 2), (2, 1, 2, 5);

TABLE uk;
TABLE fk;

--expected: fail,    behavior: deleted
DELETE FROM uk WHERE (id, s, e) = (1, 1, 3);

TABLE uk;
TABLE fk;

--expected: fail,    behavior: failed
DELETE FROM uk WHERE (id, s, e) = (1, 3, 5);

INSERT INTO uk(id, s, e)        VALUES    (2, 1, 5);
INSERT INTO fk(id, uk_id, s, e) VALUES (4, 2, 2, 4);

TABLE uk;
TABLE fk;

--expected: fail,    behavior: updated
UPDATE uk SET e = 3 WHERE (id, s, e) = (2, 1, 5);

TABLE uk;
TABLE fk;

-- Create non contiguous time -- Should fail.
INSERT INTO uk(id, s, e)        VALUES    (3, 1, 3),
                                          (3, 4, 5);
-- Reference over non contiguous time
INSERT INTO fk(id, uk_id, s, e) VALUES (5, 3, 1, 5);


-- Create overlappig range
INSERT INTO uk(id, s, e)        VALUES    (4, 1, 4),
                                          (4, 3, 5);

\set ECHO :original_ECHO
