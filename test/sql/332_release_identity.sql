-- STATBUS-452: metadata is exact-SHA, never a claim about the serving app.
\set ECHO all
SET datestyle TO 'ISO, DMY';
BEGIN;
TRUNCATE public.upgrade RESTART IDENTITY;

INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, commit_version)
VALUES (repeat('a', 40), '2099-01-01+00', ARRAY['v2099.01.0-rc.1'], 'prerelease', 'source build', 'v2099.01.0-rc.1');

-- More than the admin history cap. The old artifact remains independently resolvable.
INSERT INTO public.upgrade (commit_sha, committed_at, summary)
SELECT md5(i::text) || left(md5(i::text), 8), '2099-02-01+00'::timestamptz + i * interval '1 day', 'new candidate'
FROM generate_series(1, 101) AS i;

\echo '=== exact metadata beyond 100 history rows, without completed state ==='
SELECT * FROM public.release_identity(repeat('a', 40));
SELECT count(*) AS in_history_cap FROM (
    SELECT commit_sha FROM public.upgrade ORDER BY committed_at DESC LIMIT 100
) AS history WHERE commit_sha = repeat('a', 40);

\echo '=== no prefix or missing fallback ==='
SELECT count(*) AS prefix_matches FROM public.release_identity(repeat('a', 8));
SELECT count(*) AS missing_matches FROM public.release_identity(repeat('f', 40));

\echo '=== promotion preserves immutable build metadata ==='
UPDATE public.upgrade SET commit_tags = ARRAY['v2099.01.0-rc.1', 'v2099.01.0'], release_status = 'release'
WHERE commit_sha = repeat('a', 40);
SELECT * FROM public.release_identity(repeat('a', 40));

\echo '=== anonymous metadata access remains public and read only ==='
SET LOCAL ROLE anon;
SELECT * FROM public.release_identity(repeat('a', 40));
RESET ROLE;
SELECT state, commit_version, summary FROM public.upgrade WHERE commit_sha = repeat('a', 40);

\echo '=== pruned metadata has no newest-row substitute ==='
DELETE FROM public.upgrade WHERE commit_sha = repeat('a', 40);
SELECT count(*) AS pruned_matches FROM public.release_identity(repeat('a', 40));
ROLLBACK;
