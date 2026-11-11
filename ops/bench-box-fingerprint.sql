\set ON_ERROR_STOP on
-- ops/bench-box.sh: content fingerprint of every public table outside the import job tables, one
-- line per table: name, row count, order-independent sum of row hashes. Timestamp columns are left
-- out of each row: they record when a round ran, not what it produced. Two rounds with equal output
-- hold the same rows.
SELECT format('SELECT %L AS t, count(*) AS n, coalesce(sum(hashtextextended((to_jsonb(x) %s)::text, 0)), 0) AS h FROM %I.%I AS x',
              c.relname,
              coalesce((SELECT string_agg(format('- %L', a.attname), ' ' ORDER BY a.attnum)
                          FROM pg_attribute AS a
                         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                           AND a.atttypid IN ('timestamptz'::regtype, 'timestamp'::regtype)), ''),
              n.nspname, c.relname)
  FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition
   AND c.relname NOT LIKE 'import\_%'
 ORDER BY c.relname
\gexec
