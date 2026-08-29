BEGIN;

\i test/setup.sql

-- STATBUS-316: public.normalize_all_sequences() (migration 20260829114700)
-- resets every column-owned sequence to a position derived from the data
-- actually present, discarding whatever burn history got it there.
-- test/setup.sql above already called it once (retiring STATBUS-315's
-- narrower auth.user-only setval) -- this test proves the three properties
-- the design requires: CORRECTNESS (the exact unowned set, pinned),
-- BIDIRECTIONALITY (ahead pulled back, behind pushed forward), and
-- DETERMINISM (two different burn states on the same data converge to the
-- identical final position).

\echo -- CORRECTNESS: the exact unowned-sequence set, pinned. A sequence
\echo -- landing here or leaving here is a real schema change that this
\echo -- test must be updated to reflect -- never a silent drift.
SELECT n.nspname || '.' || c.relname AS seq
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
EXCEPT
SELECT sn.nspname || '.' || s.relname
FROM pg_class s
JOIN pg_namespace sn ON sn.oid = s.relnamespace
JOIN pg_depend d ON d.objid = s.oid
                 AND d.classid = 'pg_class'::regclass
                 AND d.refclassid = 'pg_class'::regclass
JOIN pg_class t ON t.oid = d.refobjid
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
WHERE s.relkind = 'S' AND d.deptype IN ('a', 'i')
ORDER BY 1;

\echo -- worker_task_priority_seq specifically must be in that set (named in the ticket).
SELECT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'worker_task_priority_seq' AND c.relkind = 'S'
) AS worker_task_priority_seq_exists,
NOT EXISTS (
    SELECT 1
    FROM pg_class s
    JOIN pg_namespace sn ON sn.oid = s.relnamespace
    JOIN pg_depend d ON d.objid = s.oid
                     AND d.classid = 'pg_class'::regclass
                     AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class t ON t.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
    WHERE s.relkind = 'S' AND d.deptype IN ('a', 'i')
      AND sn.nspname = 'public' AND s.relname = 'worker_task_priority_seq'
) AS worker_task_priority_seq_is_unowned;

-- Baseline: the actual max(id) currently in auth.user (test/setup.sql just
-- created the 3 fixture users and already normalized once).
SELECT max(id) AS n FROM auth."user" \gset actual_max_
\echo -- The actual max id, for reference in every assertion below.
SELECT :actual_max_n AS actual_max_user_id;

-- SCENARIO 1 -- BIDIRECTIONALITY, direction A: AHEAD pulled back. Simulate
-- burn (values consumed by rolled-back inserts elsewhere in the suite) by
-- setting the sequence far ahead of the data it actually holds.
SELECT setval(pg_get_serial_sequence('auth."user"', 'id'), :actual_max_n + 500, true);
SELECT last_value AS n FROM auth.user_id_seq \gset ahead_before_
CALL public.normalize_all_sequences();
SELECT last_value AS n FROM auth.user_id_seq \gset ahead_after_

\echo -- SCENARIO 1 assertion: was artificially ahead, pulled back to the actual max.
SELECT :ahead_before_n AS forced_ahead, :ahead_after_n AS after_normalize, :actual_max_n AS actual_max,
       (:ahead_before_n > :actual_max_n) AS was_genuinely_ahead,
       (:ahead_after_n = :actual_max_n) AS pulled_back_to_actual_max;

-- SCENARIO 2 -- BIDIRECTIONALITY, direction B: BEHIND pushed forward.
-- Simulate rows loaded with explicit ids that never touched the sequence
-- (e.g. a restored dump's COPY) by setting the sequence far below the data.
SELECT setval(pg_get_serial_sequence('auth."user"', 'id'), 1, true);
SELECT last_value AS n FROM auth.user_id_seq \gset behind_before_
CALL public.normalize_all_sequences();
SELECT last_value AS n FROM auth.user_id_seq \gset behind_after_

\echo -- SCENARIO 2 assertion: was artificially behind, pushed forward to the actual max.
SELECT :behind_before_n AS forced_behind, :behind_after_n AS after_normalize, :actual_max_n AS actual_max,
       (:behind_before_n < :actual_max_n) AS was_genuinely_behind,
       (:behind_after_n = :actual_max_n) AS pushed_forward_to_actual_max;

-- SCENARIO 3 -- DETERMINISM: two different burn states on the IDENTICAL
-- underlying data (nothing changed the actual rows between scenarios 1 and
-- 2 above) converge to the IDENTICAL final position -- the ahead-then-
-- normalized value and the behind-then-normalized value must be the same
-- number, because both are derived from the same data, never from
-- whatever position the sequence happened to start at.
\echo -- SCENARIO 3 assertion: same data, two different starting burn states, identical final position.
SELECT :ahead_after_n = :behind_after_n AS determinism_holds,
       :ahead_after_n AS from_ahead, :behind_after_n AS from_behind;

-- SCENARIO 4 -- ALREADY-CORRECT -> UNTOUCHED (the settled-database negative,
-- same discipline as 312/314): calling it again when nothing has drifted
-- must not move anything.
CALL public.normalize_all_sequences();
SELECT last_value AS n FROM auth.user_id_seq \gset settled_

\echo -- SCENARIO 4 assertion: an extra call on an already-correct sequence changes nothing.
SELECT :settled_n = :behind_after_n AS settled_call_is_a_no_op;

ROLLBACK;
