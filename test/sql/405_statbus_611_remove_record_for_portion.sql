-- STATBUS-611: a user removes a unit's record over a period through the
-- for-portion-of views, as the edit form's Remove does through PostgREST:
--   PATCH /contact__for_portion_of_valid?id=eq.N {"id": null, "valid_from": S, "valid_until": E}
-- that is UPDATE ... SET id = NULL, valid_from = S, valid_until = E WHERE id = N
-- (sql_saga 1.5's delete protocol). The record is removed over exactly
-- [S, E); rows the period cuts through are split; the rest of the record's
-- history and every other record stay as they were. Runs as a regular user
-- under pg_safeupdate, as every production session does.
BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
SET client_min_messages = warning;
\set ECHO all

\echo "A legal unit from 2024 with a postal location (PO Box 100 2024-2025, PO Box 200 from 2026) and a contact"
SELECT id AS admin_id FROM auth.user WHERE email = 'test.admin@statbus.org' \gset
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
VALUES ('ENT 405', :admin_id, now()) RETURNING id AS ent_id \gset
INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
VALUES (:ent_id, 'REMOVE 405 AS', (SELECT id FROM public.status WHERE code = 'active'), true, :admin_id, now(), '2024-01-01')
RETURNING id AS lu_id \gset
INSERT INTO public.location (valid_from, valid_to, type, address_part1, country_id, legal_unit_id, edit_by_user_id, edit_at)
VALUES ('2024-01-01', '2025-12-31', 'postal', 'PO Box 100', (SELECT id FROM public.country WHERE iso_2 = 'NO'), :lu_id, :admin_id, now())
RETURNING id AS postal_id \gset
INSERT INTO public.location (id, valid_from, valid_to, type, address_part1, country_id, legal_unit_id, edit_by_user_id, edit_at)
VALUES (:postal_id, '2026-01-01', 'infinity', 'postal', 'PO Box 200', (SELECT id FROM public.country WHERE iso_2 = 'NO'), :lu_id, :admin_id, now());
INSERT INTO public.location (valid_from, valid_to, type, address_part1, country_id, legal_unit_id, edit_by_user_id, edit_at)
VALUES ('2024-01-01', 'infinity', 'physical', 'Storgata 1', (SELECT id FROM public.country WHERE iso_2 = 'NO'), :lu_id, :admin_id, now());
INSERT INTO public.contact (valid_from, valid_to, phone_number, legal_unit_id, edit_by_user_id, edit_at)
VALUES ('2024-01-01', 'infinity', '+47 100', :lu_id, :admin_id, now())
RETURNING id AS contact_id \gset

CREATE TEMP VIEW unit_records AS
SELECT 'location ' || type AS record, valid_from, valid_until, address_part1 AS value
  FROM public.location WHERE legal_unit_id = :lu_id
UNION ALL
SELECT 'contact', valid_from, valid_until, phone_number FROM public.contact WHERE legal_unit_id = :lu_id
ORDER BY record, valid_from;
GRANT SELECT ON unit_records TO PUBLIC;

SELECT * FROM unit_records;

CALL test.set_user_from_email('test.regular@statbus.org');
SELECT current_user, current_setting('safeupdate.enabled') AS safeupdate_enabled;

\echo "Remove the postal location in 2025 only: 2024 and 2026- stay, 2025 is gone"
UPDATE public.location__for_portion_of_valid
   SET id = NULL, valid_from = '2025-01-01', valid_until = '2026-01-01'
 WHERE id = :postal_id;
SELECT * FROM unit_records WHERE record = 'location postal';

\echo "Remove a period inside an open-ended row: the row is split around it"
UPDATE public.location__for_portion_of_valid
   SET id = NULL, valid_from = '2026-03-01', valid_until = '2026-06-01'
 WHERE id = :postal_id;
SELECT * FROM unit_records WHERE record = 'location postal';

\echo "The physical location and the contact are unchanged"
SELECT * FROM unit_records WHERE record <> 'location postal';

\echo "Remove the contact entirely (no period): every row of it goes"
UPDATE public.contact__for_portion_of_valid SET id = NULL WHERE id = :contact_id;
SELECT count(*) AS contact_rows_left FROM public.contact WHERE legal_unit_id = :lu_id;

\echo "Removing and changing a value at once is refused, and nothing changes"
SAVEPOINT ambiguous;
UPDATE public.location__for_portion_of_valid
   SET id = NULL, address_part1 = 'PO Box 999', valid_from = '2024-01-01', valid_until = '2025-01-01'
 WHERE id = :postal_id;
ROLLBACK TO SAVEPOINT ambiguous;
SELECT * FROM unit_records WHERE record = 'location postal';

ROLLBACK;
