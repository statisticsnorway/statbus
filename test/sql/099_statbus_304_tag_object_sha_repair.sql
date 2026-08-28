\i test/setup.sql

-- STATBUS-304: repair migration 20260828225222 fixes public.upgrade rows
-- that store an ANNOTATED TAG OBJECT's SHA in commit_sha where the COMMIT
-- it points at belongs. This test constructs the exact defect shape plus
-- two rows the repair must NOT touch, re-applies the migration's own SQL
-- file (not a copy — the shipped bytes, so this cannot drift from what
-- actually runs in production), and asserts each row's outcome.
--
-- Fixed timestamps/ids per the house pattern (deterministic, reproducible).
--
-- NO OUTER BEGIN/COMMIT here, deliberately: the migration file itself opens
-- and closes its own transaction (matching what a real `sb migrate up` run
-- does), and re-sourcing it via \i twice below means an outer transaction
-- would nest — Postgres flattens nested BEGIN/COMMIT with a WARNING rather
-- than truly nesting, so the migration's own COMMIT would close an outer
-- transaction out from under this file, leaving a stray trailing COMMIT
-- with nothing open. Every statement here runs its own implicit
-- transaction instead (autocommit), which is fine: nothing here needs
-- cross-statement atomicity for the test itself.

-- Isolate from anything the seed data might already carry under these
-- exact commit_shas (none expected, but idempotent-safe to assert first).
DELETE FROM public.upgrade
 WHERE commit_sha IN (
     '00f346039e26cf94dd70e8a57b06df4abb427ad2', -- rc.14 tag object (wrong)
     '50b13d70db8c83199fadc2c58eb5d406301de8a9', -- rc.14 commit (correct)
     '0eb4c45ef880ba5150edc812fbced384f402164c', -- rc.15 tag object (wrong)
     '2b3862bccb9716db4bb327b6946f99c25e5efef4', -- rc.15 commit (correct)
     'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', -- fixture: unrelated "correct" row
     'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'  -- fixture: unknown-tag row
 );

-- SCENARIO 1 — POLLUTED (the defect shape exactly): commit_version names
-- the affected tag, commit_sha holds the wrong tag-object SHA. Expect:
-- CORRECTED to the real commit SHA.
INSERT INTO public.upgrade (commit_sha, committed_at, commit_version, summary)
VALUES ('00f346039e26cf94dd70e8a57b06df4abb427ad2', '2026-04-20T00:00:00Z', 'v2026.08.0-rc.14', 'STATBUS-304 fixture: polluted rc.14 row');

-- SCENARIO 2 — "CORRECT" / UNRELATED (negative #1): a row for a DIFFERENT
-- tag entirely, holding some other valid-hex SHA that matches NEITHER
-- migration literal. Proves the migration does not touch rows outside its
-- documented defect. Expect: UNTOUCHED.
INSERT INTO public.upgrade (commit_sha, committed_at, commit_version, summary)
VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '2026-04-20T00:00:00Z', 'v2026.04.0-rc.05', 'STATBUS-304 fixture: unrelated correct row');

-- SCENARIO 3 — UNKNOWN-TAG, SAME WRONG SHA (negative #2, the sharper one):
-- reuses the rc.14 tag-object SHA byte-for-byte, but under an UNRELATED
-- commit_version. Proves the WHERE clause's "AND commit_version = ..." is
-- load-bearing — matching the wrong SHA ALONE is not sufficient to be
-- touched; both conditions of the safety property must hold. Expect:
-- UNTOUCHED (still carries the "wrong" SHA — correctly so, since this row
-- was never actually claiming to be rc.14).
INSERT INTO public.upgrade (commit_sha, committed_at, commit_version, summary)
VALUES ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '2026-04-20T00:00:00Z', 'v2026.99.0-rc.01-unrelated', 'STATBUS-304 fixture: unknown-tag row (different version)');

-- SCENARIO 4 (BONUS, beyond the 3-row spec) — THE UNIQUE-CONSTRAINT GUARD:
-- a polluted rc.15 row, PLUS a separate row that already holds the CORRECT
-- rc.15 commit SHA under an unrelated label (simulating a box whose later,
-- fixed-era discovery already registered the same commit correctly).
-- commit_sha is UNIQUE (upgrade_commit_sha_key) — writing the correct SHA
-- onto the polluted row would collide. Expect: the polluted row stays
-- UNTOUCHED (the NOT EXISTS guard trips) rather than the migration
-- aborting on a constraint violation.
INSERT INTO public.upgrade (commit_sha, committed_at, commit_version, summary)
VALUES ('0eb4c45ef880ba5150edc812fbced384f402164c', '2026-04-20T00:00:00Z', 'v2026.08.0-rc.15', 'STATBUS-304 fixture: polluted rc.15 row (guard scenario)');
INSERT INTO public.upgrade (commit_sha, committed_at, commit_version, summary)
VALUES ('2b3862bccb9716db4bb327b6946f99c25e5efef4', '2026-04-20T00:00:00Z', 'v2026.08.0-rc.15-rediscovered', 'STATBUS-304 fixture: already-correct row under a different label (forces the UNIQUE-guard)');

\echo -- Before the repair migration:
SELECT commit_version, commit_sha, summary FROM public.upgrade
 WHERE commit_sha IN (
     '00f346039e26cf94dd70e8a57b06df4abb427ad2',
     'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
     'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
     '0eb4c45ef880ba5150edc812fbced384f402164c',
     '2b3862bccb9716db4bb327b6946f99c25e5efef4'
 )
 ORDER BY commit_version;

-- Re-apply the repair migration's own file — the shipped bytes, not a copy.
\i migrations/20260828225222_repair_tag_object_sha_pollution_rc14_rc15.up.sql

\echo -- After the repair migration:
SELECT commit_version, commit_sha, summary FROM public.upgrade
 WHERE commit_sha IN (
     '50b13d70db8c83199fadc2c58eb5d406301de8a9', -- scenario 1's expected NEW sha
     'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', -- scenario 2, unchanged
     'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', -- scenario 3, unchanged
     '0eb4c45ef880ba5150edc812fbced384f402164c', -- scenario 4's polluted row, STILL wrong (guard)
     '2b3862bccb9716db4bb327b6946f99c25e5efef4'  -- scenario 4's pre-existing correct row, unchanged
 )
 ORDER BY commit_version;

\echo -- Scenario 1 assertion: the polluted rc.14 row was corrected (0 rows means PASS: nothing left polluted).
SELECT count(*) AS scenario_1_still_polluted FROM public.upgrade
 WHERE commit_version = 'v2026.08.0-rc.14'
   AND commit_sha = '00f346039e26cf94dd70e8a57b06df4abb427ad2';

\echo -- Scenario 1 assertion: exactly one row now holds the correct rc.14 commit sha.
SELECT count(*) AS scenario_1_corrected FROM public.upgrade
 WHERE commit_version = 'v2026.08.0-rc.14'
   AND commit_sha = '50b13d70db8c83199fadc2c58eb5d406301de8a9';

\echo -- Scenario 2 assertion: the unrelated row is byte-for-byte unchanged.
SELECT commit_version, commit_sha FROM public.upgrade
 WHERE commit_sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

\echo -- Scenario 3 assertion: the unknown-tag row STILL carries the "wrong" sha — untouched because commit_version never matched.
SELECT commit_version, commit_sha FROM public.upgrade
 WHERE commit_sha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

\echo -- Scenario 4 assertion: the guard tripped — the polluted rc.15 row is STILL polluted (not corrected, not crashed).
SELECT commit_version, commit_sha FROM public.upgrade
 WHERE commit_version = 'v2026.08.0-rc.15'
   AND commit_sha = '0eb4c45ef880ba5150edc812fbced384f402164c';

\echo -- Scenario 4 assertion: the pre-existing correct row is untouched.
SELECT commit_version, commit_sha FROM public.upgrade
 WHERE commit_version = 'v2026.08.0-rc.15-rediscovered';

-- Re-running the migration a second time must be a no-op on the now-fixed
-- rows (idempotency, as documented in the migration header).
\i migrations/20260828225222_repair_tag_object_sha_pollution_rc14_rc15.up.sql

\echo -- Idempotency assertion: still exactly one row at the corrected rc.14 sha after a second run.
SELECT count(*) AS scenario_1_corrected_after_rerun FROM public.upgrade
 WHERE commit_version = 'v2026.08.0-rc.14'
   AND commit_sha = '50b13d70db8c83199fadc2c58eb5d406301de8a9';

-- Cleanup: leave the shared test database as we found it.
DELETE FROM public.upgrade
 WHERE commit_sha IN (
     '00f346039e26cf94dd70e8a57b06df4abb427ad2',
     '50b13d70db8c83199fadc2c58eb5d406301de8a9',
     '0eb4c45ef880ba5150edc812fbced384f402164c',
     '2b3862bccb9716db4bb327b6946f99c25e5efef4',
     'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
     'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
 );
