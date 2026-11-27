-- Norway's statistical variables (s465ff). BRREG reports employees on the legal unit and on its
-- establishments about the same people, so a legal unit's employees total is the larger of its own
-- value and its establishments' sum (max), counted once. Turnover is reported on the legal unit only
-- and keeps the default, sum. Setting a rule that is already set changes nothing; a change
-- recalculates the totals once (trigger stat_definition_lu_es_rollup_recalculate).
-- The update rebuilds statistical_unit's per-variable indexes; their notices are not output here.
SET client_min_messages TO WARNING;
UPDATE public.stat_definition SET lu_es_rollup = 'max'
WHERE code = 'employees' AND lu_es_rollup IS DISTINCT FROM 'max';
RESET client_min_messages;
