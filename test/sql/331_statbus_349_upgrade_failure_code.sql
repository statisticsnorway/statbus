-- STATBUS-349 W2: typed upgrade failure codes.
BEGIN;

\pset format unaligned
\pset tuples_only on

TRUNCATE public.upgrade RESTART IDENTITY;

\echo '=== failed row round-trips a typed failure code ==='
INSERT INTO public.upgrade (
    commit_sha,
    committed_at,
    state,
    summary,
    scheduled_at,
    started_at,
    failure_code,
    error
)
VALUES (
    repeat('a', 40),
    now(),
    'failed',
    'typed failure code probe',
    now(),
    now(),
    'GIT_FETCH_FAILED_RETRYABLE',
    'git fetch failed after bounded retries'
);

SELECT state, failure_code, error
FROM public.upgrade
WHERE commit_sha = repeat('a', 40);

\echo '=== out-of-enum failure code is rejected ==='
SAVEPOINT invalid_failure_code;
\set ON_ERROR_STOP off
UPDATE public.upgrade
SET failure_code = 'NOT_A_REAL_FAILURE_CODE'
WHERE commit_sha = repeat('a', 40);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT invalid_failure_code;

SELECT failure_code
FROM public.upgrade
WHERE commit_sha = repeat('a', 40);

\echo '=== NULL failure code is allowed for legacy rows ==='
UPDATE public.upgrade
SET failure_code = NULL
WHERE commit_sha = repeat('a', 40);

SELECT failure_code IS NULL AS null_failure_code_allowed
FROM public.upgrade
WHERE commit_sha = repeat('a', 40);

ROLLBACK;
