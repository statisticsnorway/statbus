\set original_ECHO :ECHO
\set ECHO all

--
DROP TABLE IF EXISTS uk;
DROP TABLE IF EXISTS fk;
CREATE TABLE uk(id integer, v tstzrange);
CREATE TABLE fk(id integer, uk_id integer, v tstzrange);

SELECT create_temporal_foreign_key(
  'fk_has_uk_key',
  'fk',  'uk_id', 'v',
  'uk', 'id','v'
);


--
INSERT INTO uk(id, v)        VALUES    (1, '[2023-01-01,2023-03-01)'),    (1, '[2023-03-01,2023-05-01)');
INSERT INTO fk(id, uk_id, v) VALUES (1, 1, '[2023-01-01,2023-02-01)'), (2, 1, '[2023-02-01,2023-05-01)');

TABLE uk;
TABLE fk;

--expected: fail,    behavior: deleted
DELETE FROM uk WHERE (id, v) =(1, '[2023-01-01,2023-03-01)');

TABLE uk;
TABLE fk;

--expected: fail,    behavior: failed
DELETE FROM uk WHERE (id, v) = (1, '[2023-03-01,2023-05-01)');

INSERT INTO uk(id, v)        VALUES    (2, '[2023-01-01,2023-05-01)');
INSERT INTO fk(id, uk_id, v) VALUES (4, 2, '[2023-02-01,2023-04-01)');

TABLE uk;
TABLE fk;

--expected: fail,    behavior: updated
UPDATE uk SET v = '[2023-01-01,2023-03-01)' WHERE (id, v) = (2, '[2023-01-01,2023-05-01)');

TABLE uk;
TABLE fk;

\set ECHO :original_ECHO