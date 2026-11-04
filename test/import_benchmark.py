#!/usr/bin/env python3
"""
Benchmark the BRREG import through the real worker, in an isolated database.

1. Creates an isolated DB from the test template (POSTGRES_TEST_DB or statbus_test_template)
2. Loads the dataset with its loader script (samples/norway/brreg/), the same
   script ./cloud.sh import runs on an installation
3. Runs the real worker binary with --stop-when-idle
4. Reports the time per command, checks counts, records benchmarks, and replays
   each child command repeatedly to catch plans that degrade after the 5th call

Run with: ./test/import_benchmark.sh [--dataset selection|downloads] [-t TIMEOUT]
"""

import os
import sys
import time
import signal
import subprocess
import argparse
import atexit
import logging
import threading
from pathlib import Path

import psycopg2
import psycopg2.extras

# ============================================================================
# Configuration
# ============================================================================

WORKSPACE = Path(__file__).parent.parent.absolute()
TEMPLATE_DB = os.environ.get("POSTGRES_TEST_DB", "statbus_test_template")
MANAGE = str(WORKSPACE / "sb")
ENV_CONFIG = WORKSPACE / ".env.config"

# Colors
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'


# Global test database name (set during setup)
TEST_DB = None
LOG_FILE = None


def setup_logging():
    """Setup logging to both console and tmp/ log file"""
    global LOG_FILE
    tmp_dir = WORKSPACE / "tmp"
    tmp_dir.mkdir(exist_ok=True)
    LOG_FILE = tmp_dir / f"import_benchmark_{os.getpid()}.log"

    # Create logger
    logger = logging.getLogger("concurrent_worker")
    logger.setLevel(logging.DEBUG)

    # File handler - verbose, no colors
    fh = logging.FileHandler(LOG_FILE, mode='w')
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
    logger.addHandler(fh)

    return logger


# Initialize logger
log = setup_logging()


def log_print(msg, level="info"):
    """Print to console AND write to log file"""
    print(msg)
    # Strip color codes for log file
    clean = msg
    for code in [RED, GREEN, YELLOW, BLUE, NC]:
        clean = clean.replace(code, '')
    getattr(log, level)(clean)


def get_pg_env():
    """Get PostgreSQL connection env vars by evaluating sb config show --postgres"""
    result = subprocess.run(
        [MANAGE, "config", "show", "--postgres"],
        capture_output=True, text=True, cwd=WORKSPACE
    )
    if result.returncode != 0:
        raise Exception(f"Failed to get config show --postgres: {result.stderr}")

    env = os.environ.copy()
    # Parse: export PGHOST=x PGPORT=y PGDATABASE=z PGUSER=u PGPASSWORD=p ...
    line = result.stdout.strip()
    if line.startswith("export "):
        line = line[len("export "):]
    for part in line.split():
        if '=' in part:
            key, value = part.split('=', 1)
            env[key] = value
    return env


PG_ENV = None


def pg_env():
    global PG_ENV
    if PG_ENV is None:
        PG_ENV = get_pg_env()
    return PG_ENV


def get_conn(dbname=None):
    """Create a psycopg2 connection using the same credentials as sb psql"""
    env = pg_env()
    return psycopg2.connect(
        host=env.get("PGHOST", "localhost"),
        port=int(env.get("PGPORT", "5432")),
        dbname=dbname or TEST_DB or env.get("PGDATABASE"),
        user=env.get("PGUSER", "postgres"),
        password=env.get("PGPASSWORD"),
        sslmode=env.get("PGSSLMODE", "disable"),
    )


def run_psql(sql, dbname=None):
    """Run SQL via sb psql"""
    db = dbname or TEST_DB
    cmd = [MANAGE, "psql", "-d", db, "-v", "ON_ERROR_STOP=1"]
    log.debug(f"psql -d {db}: {sql[:200]}...")
    result = subprocess.run(
        cmd, input=sql, text=True, capture_output=True, cwd=WORKSPACE
    )
    if result.stdout:
        log.debug(f"psql stdout: {result.stdout[:500]}")
    if result.returncode != 0:
        log_print(f"{RED}psql error:{NC}\n{result.stderr}", "error")
        raise Exception(f"psql failed with exit code {result.returncode}")
    return result.stdout


def run_psql_file(filepath, dbname=None):
    """Run SQL file via sb psql"""
    db = dbname or TEST_DB
    cmd = [MANAGE, "psql", "-d", db, "-v", "ON_ERROR_STOP=1", "-f", filepath]
    log.debug(f"psql -d {db} -f {filepath}")
    result = subprocess.run(cmd, text=True, capture_output=True, cwd=WORKSPACE)
    if result.stdout:
        log.debug(f"psql stdout: {result.stdout[:500]}")
    if result.returncode != 0:
        log_print(f"{RED}psql error running {filepath}:{NC}\n{result.stderr}", "error")
        raise Exception(f"psql -f {filepath} failed with exit code {result.returncode}")
    return result.stdout


# ============================================================================
# Database Setup/Teardown
# ============================================================================

def create_isolated_db():
    """Create isolated test database from template"""
    global TEST_DB
    TEST_DB = f"import_benchmark_{os.getpid()}"

    log_print(f"{BLUE}Creating isolated database: {TEST_DB}{NC}")

    conn = get_conn(dbname="postgres")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SELECT pg_advisory_lock(59328)")
        cur.execute(f"ALTER DATABASE {TEMPLATE_DB} WITH ALLOW_CONNECTIONS = true")
        cur.execute(f'CREATE DATABASE "{TEST_DB}" WITH TEMPLATE {TEMPLATE_DB}')
        cur.execute(f"ALTER DATABASE {TEMPLATE_DB} WITH ALLOW_CONNECTIONS = false")
        cur.execute("SELECT pg_advisory_unlock(59328)")
    conn.close()

    log_print(f"{GREEN}Database created: {TEST_DB}{NC}")
    return TEST_DB


def drop_isolated_db(force=False):
    """Drop the isolated test database"""
    if not TEST_DB:
        return

    # Default: KEEP database for comparison across runs
    if not force:
        log_print(f"\n{BLUE}Database retained: {TEST_DB}{NC}")
        log_print(f"  Inspect: {MANAGE} psql -d {TEST_DB}")
        log_print(f"  Delete:  {MANAGE} psql -d postgres -c \"DROP DATABASE \\\"{TEST_DB}\\\"\"")
        return

    log_print(f"{YELLOW}Dropping database: {TEST_DB}{NC}")
    try:
        conn = get_conn(dbname="postgres")
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '{TEST_DB}' AND pid != pg_backend_pid()
            """)
            cur.execute(f'DROP DATABASE IF EXISTS "{TEST_DB}"')
        conn.close()
        log_print(f"{GREEN}Database dropped: {TEST_DB}{NC}")
    except Exception as e:
        log_print(f"{YELLOW}Warning: Failed to drop database: {e}{NC}", "warning")


def drop_all_test_databases():
    """Drop ALL import_benchmark_* databases"""
    conn = get_conn(dbname="postgres")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("""
            SELECT datname FROM pg_database
            WHERE datname LIKE 'import_benchmark_%'
            ORDER BY datname
        """)
        dbs = [row[0] for row in cur.fetchall()]

        if not dbs:
            log_print("No import_benchmark_* databases found.")
            conn.close()
            return

        log_print(f"Dropping {len(dbs)} test databases...")
        for db in dbs:
            try:
                cur.execute(f"""
                    SELECT pg_terminate_backend(pid)
                    FROM pg_stat_activity
                    WHERE datname = '{db}' AND pid != pg_backend_pid()
                """)
                cur.execute(f'DROP DATABASE IF EXISTS "{db}"')
                log_print(f"  {GREEN}Dropped: {db}{NC}")
            except Exception as e:
                log_print(f"  {RED}Failed to drop {db}: {e}{NC}", "error")
    conn.close()


# ============================================================================
# Dataset configurations
# ============================================================================

DATASETS = {
    "selection": {
        "description": "BRREG selection (~29K rows, like test 401)",
        "loader": "samples/norway/brreg/brreg-import-selection.sh",
        "files": [
            "samples/norway/legal_unit/enheter-selection.csv",
            "samples/norway/establishment/underenheter-selection.csv",
            "samples/norway/legal_relationship/roller-selection.csv",
        ],
        "slug_like": "import_%_selection",
    },
    "downloads": {
        "description": "BRREG full downloads (~2.4M rows, the files in tmp/)",
        "loader": "samples/norway/brreg/brreg-import-downloads-from-tmp.sh",
        "files": [
            "tmp/enheter.csv",
            "tmp/underenheter_filtered.csv",
        ],
        "slug_like": "import_%_2025",
    },
}


def setup_test_data(dataset="selection"):
    """Load the dataset through its loader script, the same one ./cloud.sh
    import runs on an installation, into this run's isolated database."""
    ds = DATASETS[dataset]

    log_print(f"\n{BLUE}Setting up test data: {ds['description']}...{NC}")

    for path in ds["files"]:
        full_path = WORKSPACE / path
        if not full_path.exists():
            log_print(f"{RED}ERROR: CSV not found: {full_path}{NC}", "error")
            if dataset == "downloads":
                log_print("  Download with samples/norway/brreg/download-to-tmp.sh", "error")
            sys.exit(1)
        size_mb = full_path.stat().st_size / (1024 * 1024)
        log_print(f"  {path} ({size_mb:.1f} MB)")

    # The loader needs a user to own the jobs; test/setup.sql creates
    # test.admin@statbus.org in the isolated database.
    log_print("  Running test/setup.sql...")
    run_psql_file("test/setup.sql")

    log_print(f"  Running {ds['loader']} --database {TEST_DB}...")
    env = os.environ.copy()
    env["USER_EMAIL"] = "test.admin@statbus.org"
    result = subprocess.run(
        [str(WORKSPACE / ds["loader"]), "--database", TEST_DB],
        cwd=WORKSPACE, env=env, text=True, capture_output=True,
    )
    log.debug(result.stdout)
    if result.returncode != 0:
        log_print(f"{RED}Loader failed ({result.returncode}):{NC}\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}", "error")
        sys.exit(1)

    # Show task state
    log_print(f"\n{BLUE}Test data loaded. Task states:{NC}")
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT state, count(*)
            FROM worker.tasks
            GROUP BY state ORDER BY state
        """)
        for row in cur.fetchall():
            log_print(f"  {row[0]}: {row[1]}")

        cur.execute("""
            SELECT slug, state, total_rows
            FROM public.import_job
            WHERE slug LIKE %s
            ORDER BY slug
        """, (ds["slug_like"],))
        log_print(f"\n{BLUE}Import jobs:{NC}")
        for row in cur.fetchall():
            log_print(f"  {row[0]}: state={row[1]}, rows={row[2]}")
    conn.close()




# ============================================================================
# Worker Execution
# ============================================================================

def run_worker(test_db, timeout_seconds=300, debug=True):
    """Start the real Crystal worker binary against the test database.

    The worker runs with --stop-when-idle which makes it exit after
    all queues have been idle for 3 consecutive seconds.

    Timeout: sends SIGTERM after timeout_seconds, then SIGKILL after 10s grace.
    Output is streamed in a background thread so the timeout is not blocked.
    """
    binary = WORKSPACE / "cli" / "bin" / "statbus"
    if not binary.exists():
        log_print(f"{RED}Worker binary not found: {binary}{NC}", "error")
        log_print(f"  Build with: cd cli && shards build statbus", "error")
        sys.exit(1)

    cmd = [str(binary), "worker", "--stop-when-idle", "--database", test_db]
    env = os.environ.copy()
    if debug:
        env["DEBUG"] = "1"

    log_print(f"\n{BLUE}Starting worker: {' '.join(cmd)}{NC}")
    start = time.time()

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, env=env, cwd=str(WORKSPACE)
    )

    # Stream output in a background thread so the main thread can enforce timeout
    output_lines = []

    def stream_output():
        try:
            for line in proc.stdout:
                line = line.rstrip('\n')
                output_lines.append(line)
                log_print(f"  [worker] {line}")
        except Exception as e:
            log_print(f"{YELLOW}Error reading worker output: {e}{NC}", "warning")

    reader = threading.Thread(target=stream_output, daemon=True)
    reader.start()

    # Wait for process with actual timeout enforcement
    timed_out = False
    try:
        proc.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        log_print(f"\n{RED}Worker timed out after {timeout_seconds}s, sending SIGTERM...{NC}", "error")
        proc.terminate()  # SIGTERM — let worker shut down gracefully
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            log_print(f"{RED}Worker did not exit after SIGTERM, sending SIGKILL...{NC}", "error")
            proc.kill()
            proc.wait()

    # Wait for reader thread to finish draining output
    reader.join(timeout=5)

    elapsed = time.time() - start

    if timed_out:
        log_print(f"\n{RED}Worker KILLED after {elapsed:.1f}s (timeout: {timeout_seconds}s){NC}")
    else:
        log_print(f"\n{BLUE}Worker exited with code {proc.returncode} in {elapsed:.1f}s{NC}")
    return proc.returncode, output_lines, elapsed


def run_concurrent_test(timeout_seconds=300, debug=True):
    """Run the real Crystal worker and verify results."""
    log_print(f"\n{'='*60}")
    log_print(f"  Concurrent Worker Test (real Crystal worker)")
    log_print(f"  Database: {TEST_DB}")
    log_print(f"  Timeout: {timeout_seconds}s")
    log_print(f"  Log: {LOG_FILE}")
    log_print(f"{'='*60}")

    returncode, output, elapsed = run_worker(TEST_DB, timeout_seconds, debug)

    # Query final task states
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT state, count(*)
            FROM worker.tasks
            GROUP BY state ORDER BY state
        """)
        log_print(f"\n  Final task states:")
        for row in cur.fetchall():
            log_print(f"    {row[0]}: {row[1]}")

        # Check for failed tasks
        cur.execute("""
            SELECT id, command, error
            FROM worker.tasks
            WHERE state = 'failed'
            ORDER BY id
            LIMIT 10
        """)
        failed = cur.fetchall()
        if failed:
            log_print(f"\n  {RED}Failed tasks:{NC}")
            for row in failed:
                log_print(f"    Task {row[0]} ({row[1]}): {row[2]}", "error")

        # Pipeline timing breakdown
        cur.execute("""
            SELECT command
                 , count(*) AS tasks
                 , sum(process_duration_ms)::numeric(10,0) AS total_ms
                 , min(process_duration_ms)::numeric(10,0) AS min_ms
                 , max(process_duration_ms)::numeric(10,0) AS max_ms
                 , avg(process_duration_ms)::numeric(10,1) AS avg_ms
            FROM worker.tasks
            WHERE state = 'completed' AND process_duration_ms IS NOT NULL
            GROUP BY command
            ORDER BY total_ms DESC
        """)
        timing_rows = cur.fetchall()
        if timing_rows:
            # The loader creates one job per file and the worker finishes them
            # one after another, so analytics run once per finished job
            # (serialised cycles), as on a real installation. Before
            # STATBUS-198 the runner created all jobs at once: one cycle.
            cur.execute("SELECT count(*) FROM worker.tasks WHERE command = 'derive_statistical_unit'")
            cycles = cur.fetchone()[0]
            log_print(f"\n  {BLUE}Pipeline timing breakdown ({cycles} serialised analytics cycle(s), one per finished import job):{NC}")
            log_print(f"    {'Command':<50} {'#':>4} {'Total':>8} {'Min':>8} {'Max':>8} {'Avg':>8}")
            log_print(f"    {'-'*50} {'----':>4} {'--------':>8} {'--------':>8} {'--------':>8} {'--------':>8}")
            for row in timing_rows:
                cmd, tasks, total, mn, mx, avg = row
                log_print(f"    {cmd:<50} {tasks:>4} {total:>7}ms {mn:>7}ms {mx:>7}ms {avg:>7}ms")
            # Grand total
            grand_total = sum(r[2] for r in timing_rows)
            grand_tasks = sum(r[1] for r in timing_rows)
            log_print(f"    {'-'*50} {'----':>4} {'--------':>8}")
            log_print(f"    {'TOTAL':<50} {grand_tasks:>4} {grand_total:>7}ms")
    conn.close()

    # Concurrency-corruption gate — three layers
    consistent, consistency_summary = check_consistency()

    # Run hierarchy function benchmarks (after analytics pipeline is complete)
    if not failed:
        run_hierarchy_benchmarks()

    plans_stable = run_repeated_call_benchmarks() if not failed else True

    success = returncode == 0 and not failed and consistent and plans_stable
    if success:
        log_print(f"\n{GREEN}{'='*60}")
        log_print(f"  SUCCESS: Worker processed all tasks in {elapsed:.1f}s; counts consistent")
        log_print(f"{'='*60}{NC}")
    else:
        log_print(f"\n{RED}{'='*60}")
        log_print(f"  FAILED: returncode={returncode}, failed_tasks={len(failed)}, consistent={consistent}")
        if not consistent:
            log_print(f"  {consistency_summary}", "error")
        log_print(f"{'='*60}{NC}")
    return success


def check_consistency():
    """Verify post-run statistical_history is internally and externally consistent.

    Three layers of check (STATBUS-558: the history tables are sparse deltas,
    statistical_history and statistical_history_facet are views over them):
      A. Incremental == rebuild: the stored history_stock_delta and
         history_flow_delta rows, maintained cycle by cycle, equal a full
         rebuild from statistical_unit (computed in a rolled-back transaction),
         unit_ids included. Fails when a cycle staged a wrong delta or missed one.
      B. Ground-truth: sh.exists_count == COUNT(DISTINCT unit_id) from
         statistical_unit at the corresponding year-end. Catches stale rows.
      C. Staging drained: no staged delta row is left after the last reduce.

    Returns (consistent: bool, summary: str). Logs detail per layer.
    """
    log_print(f"\n  {BLUE}Consistency checks:{NC}")

    rows_sql = """
        SELECT 'stock', unit_type::text, primary_activity_category_path::text, secondary_activity_category_path::text,
               sector_path::text, legal_form_id, physical_region_path::text, physical_country_id, unit_size_id,
               status_id, on_month::text, exists_delta, countable_delta,
               -- stats as net in - out per variable (a side absent from the delta counts as 0): the gross
               -- flows depend on the path of changes, the net is the stock the row contributes.
               (SELECT string_agg(x.key || ':' || x.n || ',' || x.s, ';' ORDER BY x.key)
                  FROM (SELECT e.key,
                               COALESCE((e.value->'in'->>'count')::numeric, 0) - COALESCE((e.value->'out'->>'count')::numeric, 0) AS n,
                               COALESCE((e.value->'in'->>'sum')::numeric, 0) - COALESCE((e.value->'out'->>'sum')::numeric, 0) AS s
                          FROM jsonb_each(COALESCE(stats_delta, '{}') - 'type'::text) AS e) AS x
                 WHERE x.n <> 0 OR x.s <> 0), unit_ids::text
          FROM public.history_stock_delta
        UNION ALL
        SELECT 'flow', unit_type::text, primary_activity_category_path::text, secondary_activity_category_path::text,
               sector_path::text, legal_form_id, physical_region_path::text, physical_country_id, unit_size_id,
               status_id, resolution::text || year || '-' || COALESCE(month, 0), NULL, NULL, flows::text, unit_ids::text
          FROM public.history_flow_delta
    """

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SET ROLE postgres")  # staging tables have no grants for API roles

            # --- Layer C: staging drained ---
            cur.execute("""
                SELECT (SELECT count(*) FROM public.history_stock_delta_staging)
                     + (SELECT count(*) FROM public.history_flow_delta_staging)
            """)
            orphan_count = cur.fetchone()[0]

            # --- Layer A: incremental == rebuild (rolled back) ---
            cur.execute(f"CREATE TEMP TABLE bench_incremental AS {rows_sql}")
            cur.execute("""
                TRUNCATE public.history_stock_delta, public.history_flow_delta,
                         public.history_stock_delta_staging, public.history_flow_delta_staging
            """)
            cur.execute("CALL worker.history_delta_range('[0,16384)'::int4range, true)")
            cur.execute("CALL worker.history_delta_apply()")
            cur.execute(f"CREATE TEMP TABLE bench_rebuilt AS {rows_sql}")
            cur.execute("""
                SELECT 'only_incremental', * FROM (SELECT * FROM bench_incremental EXCEPT ALL SELECT * FROM bench_rebuilt) AS a
                UNION ALL
                SELECT 'only_rebuild', * FROM (SELECT * FROM bench_rebuilt EXCEPT ALL SELECT * FROM bench_incremental) AS b
            """)
            internal_divergent = cur.fetchall()
            conn.rollback()
            cur.execute("SET ROLE postgres")

            # --- Layer B: ground-truth via statistical_unit at year-end ---
            # Truth predicate: the existence rule (STATBUS-460) at the year-end, as the
            # history stock counts it: slice covers year-end AND birth_date <= year-end
            # AND (death_date IS NULL OR death_date > year-end).
            cur.execute("""
                WITH years AS (
                    SELECT DISTINCT year FROM public.statistical_history
                    WHERE resolution = 'year'
                )
                SELECT y.year, sh.unit_type, sh.exists_count, sh.countable_count,
                    (SELECT COUNT(DISTINCT su.unit_id)
                       FROM public.statistical_unit AS su
                       WHERE su.unit_type = sh.unit_type
                         AND su.valid_from <= make_date(y.year, 12, 31)
                         AND su.valid_until > make_date(y.year, 12, 31)
                         AND COALESCE(su.birth_date, su.valid_from) <= make_date(y.year, 12, 31)
                         AND (su.death_date IS NULL OR su.death_date > make_date(y.year, 12, 31))) AS truth_exists,
                    (SELECT COUNT(DISTINCT su.unit_id)
                       FROM public.statistical_unit AS su
                       WHERE su.unit_type = sh.unit_type
                         AND su.valid_from <= make_date(y.year, 12, 31)
                         AND su.valid_until > make_date(y.year, 12, 31)
                         AND COALESCE(su.birth_date, su.valid_from) <= make_date(y.year, 12, 31)
                         AND (su.death_date IS NULL OR su.death_date > make_date(y.year, 12, 31))
                         AND su.used_for_counting) AS truth_countable
                FROM years AS y
                JOIN public.statistical_history AS sh
                  ON sh.resolution = 'year' AND sh.year = y.year
                ORDER BY y.year, sh.unit_type
            """)
            truth_rows = cur.fetchall()
            truth_divergent = [r for r in truth_rows if r[2] != r[4] or r[3] != r[5]]
    finally:
        conn.close()

    consistent = (orphan_count == 0
                  and len(internal_divergent) == 0
                  and len(truth_divergent) == 0)

    # Layer C report
    if orphan_count == 0:
        log_print(f"    {GREEN}C staging drained: 0 staged history rows left — pass{NC}")
    else:
        log_print(f"    {RED}C staging not drained: {orphan_count} staged history rows left — FAIL{NC}", "error")

    # Layer A report
    if not internal_divergent:
        log_print(f"    {GREEN}A incremental == rebuild: 0 divergent delta rows — pass{NC}")
    else:
        log_print(f"    {RED}A incremental != rebuild: {len(internal_divergent)} divergent delta rows — FAIL{NC}", "error")
        for r in internal_divergent[:10]:
            log_print(f"      {r}")

    # Layer B report
    if not truth_divergent:
        log_print(f"    {GREEN}B SH vs ground-truth statistical_unit: 0 divergent — pass{NC}")
    else:
        log_print(f"    {RED}B SH vs ground-truth: {len(truth_divergent)} divergent — FAIL{NC}", "error")
        log_print(f"      {'year':>4} {'unit_type':<12} {'sh_exists':>10} {'truth':>6} {'sh_countable':>13} {'truth':>6}")
        for r in truth_divergent[:10]:
            log_print(f"      {r[0]:>4} {r[1]:<12} {r[2]:>10} {r[4]:>6} {r[3]:>13} {r[5]:>6}")

    summary = (f"staged_left={orphan_count} "
               f"internal_divergent={len(internal_divergent)} "
               f"truth_divergent={len(truth_divergent)}")
    return consistent, summary


def run_hierarchy_benchmarks():
    """Run EXPLAIN ANALYZE benchmarks for hierarchy functions and write to perf file."""
    perf_dir = WORKSPACE / "test" / "expected" / "performance"
    perf_dir.mkdir(parents=True, exist_ok=True)
    perf_file = perf_dir / "import_benchmark_hierarchy.perf"

    log_print(f"\n{BLUE}Running hierarchy function benchmarks...{NC}")

    conn = get_conn()
    conn.autocommit = True
    with conn.cursor() as cur:
        # Pick the enterprise with the most establishments (deepest hierarchy)
        cur.execute("""
            SELECT su.unit_id
            FROM public.statistical_unit AS su
            WHERE su.unit_type = 'enterprise'
              AND su.valid_from <= '2025-01-01' AND '2025-01-01' < su.valid_until
            ORDER BY su.stats -> 'establishment_count' -> 'count' DESC NULLS LAST
            LIMIT 1
        """)
        row = cur.fetchone()
        if not row:
            log_print(f"{YELLOW}No enterprise found for benchmarks, skipping.{NC}", "warning")
            conn.close()
            return
        ent_id = row[0]

        # Pick a legal_unit with the most establishments
        cur.execute("""
            SELECT su.unit_id
            FROM public.statistical_unit AS su
            WHERE su.unit_type = 'legal_unit'
              AND su.valid_from <= '2025-01-01' AND '2025-01-01' < su.valid_until
            ORDER BY su.stats -> 'establishment_count' -> 'count' DESC NULLS LAST
            LIMIT 1
        """)
        row = cur.fetchone()
        if not row:
            log_print(f"{YELLOW}No legal_unit found for benchmarks, skipping.{NC}", "warning")
            conn.close()
            return
        lu_id = row[0]

        log_print(f"  Enterprise unit_id={ent_id}, Legal unit unit_id={lu_id}")

        # Run 4 EXPLAIN ANALYZE queries
        benchmarks = [
            ("statistical_unit_stats (legal_unit)",
             "EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_stats('legal_unit', %s, '2025-01-01'::DATE)",
             lu_id),
            ("statistical_unit_stats (enterprise)",
             "EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_stats('enterprise', %s, '2025-01-01'::DATE)",
             ent_id),
            ("relevant_statistical_units (legal_unit)",
             "EXPLAIN ANALYZE SELECT * FROM public.relevant_statistical_units('legal_unit', %s, '2025-01-01'::DATE)",
             lu_id),
            ("relevant_statistical_units (enterprise)",
             "EXPLAIN ANALYZE SELECT * FROM public.relevant_statistical_units('enterprise', %s, '2025-01-01'::DATE)",
             ent_id),
        ]

        lines = []
        lines.append("# Benchmark: statistical_unit_stats and relevant_statistical_units (~29K rows)")
        cur.execute("SELECT now()::text")
        lines.append(f"# Date: {cur.fetchone()[0]}")
        lines.append("")

        for label, query, unit_id in benchmarks:
            lines.append(f"## EXPLAIN ANALYZE: {label}")
            cur.execute(query, (unit_id,))
            rows = cur.fetchall()
            for r in rows:
                lines.append(r[0])

            # Extract execution time from last line
            plan_text = rows[-1][0] if rows else ""
            if "Execution Time:" in plan_text:
                log_print(f"  {label}: {plan_text.strip()}")

            lines.append("")

    conn.close()

    # Write perf file
    with open(perf_file, "w") as f:
        f.write("\n".join(lines))

    log_print(f"  Benchmark results written to: {perf_file.relative_to(WORKSPACE)}")


# A worker fiber keeps one database session and runs one task after another in
# it. From the sixth execution PL/pgSQL may switch a statement to a generic plan
# that ignores the parameter values; for a command whose best plan depends on
# those values, every later task then runs slower (STATBUS-555: the history
# period child went from 60 ms to 3.5 s). A single EXPLAIN in a fresh session
# never sees that plan, so each child command is replayed here as the worker
# runs it: eight calls in one session with the payload of a completed task.
REPEATED_CALLS = 8
# PostgreSQL's plan cache considers a generic plan from the sixth execution
# in a session; a command the import runs fewer times never meets one.
GENERIC_PLAN_FROM_CALL = 6
REPEATED_CALL_MAX_RATIO = 3.0


def run_repeated_call_benchmarks():
    """Record first-call vs last-call time per child command in one session.

    Returns False when a command's last call is more than
    REPEATED_CALL_MAX_RATIO times slower than its first.
    """
    perf_dir = WORKSPACE / "test" / "expected" / "performance"
    perf_dir.mkdir(parents=True, exist_ok=True)
    perf_file = perf_dir / "import_benchmark_repeated_calls.perf"

    log_print(f"\n{BLUE}Replaying each child command {REPEATED_CALLS} times in one session...{NC}")

    conn = get_conn()
    conn.autocommit = False
    rows = []
    with conn.cursor() as cur:
        # Only commands this run executed at least GENERIC_PLAN_FROM_CALL
        # times: a plan can only switch to generic from then on, so a
        # command run a handful of times per import (the reduce steps) never
        # reaches it, and replaying their whole-table work eight times only
        # measures memory pressure.
        cur.execute("""
            SELECT DISTINCT ON (t.command) t.command, c.handler_procedure, t.payload
              FROM worker.tasks AS t
              JOIN worker.command_registry AS c USING (command)
             WHERE t.state = 'completed' AND t.parent_id IS NOT NULL
               AND t.command IN (
                     SELECT command FROM worker.tasks
                      WHERE state = 'completed'
                      GROUP BY command HAVING count(*) >= %s)
             ORDER BY t.command, t.id DESC
        """, (GENERIC_PLAN_FROM_CALL,))
        commands = cur.fetchall()
        conn.rollback()
        for command, procedure, payload in commands:
            times_ms = []
            for _ in range(REPEATED_CALLS):
                # One transaction per call, rolled back, as the worker commits
                # each task: the plan cache lives in the session, so repeated
                # calls still reach the generic plan, while row versions and
                # locks do not pile up in one transaction and skew the timing.
                start = time.perf_counter()
                cur.execute(f"CALL {procedure}(%s::jsonb)", (psycopg2.extras.Json(payload),))
                times_ms.append((time.perf_counter() - start) * 1000)
                conn.rollback()
            first, last = times_ms[0], times_ms[-1]
            ratio = last / first if first > 0 else 0.0
            rows.append((command, first, last, ratio))
    conn.close()

    flipped = [r for r in rows if r[3] > REPEATED_CALL_MAX_RATIO]
    lines = [
        f"# Repeated calls of each child command in one session ({REPEATED_CALLS} calls)",
        f"# Flag: last call more than {REPEATED_CALL_MAX_RATIO}x the first (a generic plan worse than the custom one)",
        f"# Commands run fewer than {GENERIC_PLAN_FROM_CALL} times in the import are not replayed.",
        "",
        f"{'command':<45} {'first_ms':>10} {'last_ms':>10} {'ratio':>7}",
    ]
    for command, first, last, ratio in sorted(rows):
        flag = "  FLIPPED" if ratio > REPEATED_CALL_MAX_RATIO else ""
        lines.append(f"{command:<45} {first:>10.1f} {last:>10.1f} {ratio:>7.2f}{flag}")
        log_print(f"  {command:<45} first {first:>8.1f} ms  last {last:>8.1f} ms  x{ratio:.2f}{flag}")
    with open(perf_file, "w") as f:
        f.write("\n".join(lines) + "\n")
    log_print(f"  Repeated-call results written to: {perf_file.relative_to(WORKSPACE)}")

    if flipped:
        log_print(f"{RED}  {len(flipped)} command(s) slow down on repeated calls: "
                  f"{', '.join(r[0] for r in flipped)}{NC}", "error")
    return not flipped


def list_test_databases():
    """List existing test databases"""
    conn = get_conn(dbname="postgres")
    with conn.cursor() as cur:
        cur.execute("""
            SELECT datname, pg_size_pretty(pg_database_size(datname))
            FROM pg_database
            WHERE datname LIKE 'import_benchmark_%'
            ORDER BY datname
        """)
        rows = cur.fetchall()
        if rows:
            print("Existing test databases:")
            for row in rows:
                print(f"  {row[0]} ({row[1]})")
        else:
            print("No import_benchmark_* databases found.")
    conn.close()


def show_timing(dbname):
    """Show pipeline timing from a persisted test database."""
    conn = get_conn(dbname=dbname)
    with conn.cursor() as cur:
        cur.execute("""
            SELECT state, count(*)
            FROM worker.tasks
            GROUP BY state ORDER BY state
        """)
        log_print(f"\n  Task states in {dbname}:")
        for row in cur.fetchall():
            log_print(f"    {row[0]}: {row[1]}")

        cur.execute("""
            SELECT command
                 , count(*) AS tasks
                 , sum(process_duration_ms)::numeric(10,0) AS total_ms
                 , min(process_duration_ms)::numeric(10,0) AS min_ms
                 , max(process_duration_ms)::numeric(10,0) AS max_ms
                 , avg(process_duration_ms)::numeric(10,1) AS avg_ms
            FROM worker.tasks
            WHERE state = 'completed' AND process_duration_ms IS NOT NULL
            GROUP BY command
            ORDER BY total_ms DESC
        """)
        timing_rows = cur.fetchall()
        if timing_rows:
            # The loader creates one job per file and the worker finishes them
            # one after another, so analytics run once per finished job
            # (serialised cycles), as on a real installation. Before
            # STATBUS-198 the runner created all jobs at once: one cycle.
            cur.execute("SELECT count(*) FROM worker.tasks WHERE command = 'derive_statistical_unit'")
            cycles = cur.fetchone()[0]
            log_print(f"\n  {BLUE}Pipeline timing breakdown ({cycles} serialised analytics cycle(s), one per finished import job):{NC}")
            log_print(f"    {'Command':<50} {'#':>4} {'Total':>8} {'Min':>8} {'Max':>8} {'Avg':>8}")
            log_print(f"    {'-'*50} {'----':>4} {'--------':>8} {'--------':>8} {'--------':>8} {'--------':>8}")
            for row in timing_rows:
                cmd, tasks, total, mn, mx, avg = row
                log_print(f"    {cmd:<50} {tasks:>4} {total:>7}ms {mn:>7}ms {mx:>7}ms {avg:>7}ms")
            grand_total = sum(r[2] for r in timing_rows)
            grand_tasks = sum(r[1] for r in timing_rows)
            log_print(f"    {'-'*50} {'----':>4} {'--------':>8}")
            log_print(f"    {'TOTAL':<50} {grand_tasks:>4} {grand_total:>7}ms")
        else:
            log_print("  No completed tasks with timing data found.")
    conn.close()


# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Test concurrent worker processing with isolated database",
        epilog="Databases are RETAINED by default for comparison. Use --cleanup to delete."
    )
    parser.add_argument("-t", "--timeout", type=int, default=600,
                        help="Worker timeout in seconds (default: 600)")
    parser.add_argument("--skip-setup", action="store_true",
                        help="Skip DB creation and data load (use current PGDATABASE)")
    parser.add_argument("--cleanup", action="store_true",
                        help="Delete test database after run")
    parser.add_argument("--list", action="store_true",
                        help="List existing test databases and exit")
    parser.add_argument("--dataset", choices=list(DATASETS.keys()), default="selection",
                        help="Dataset to use: " + ", ".join(
                            f"{k} ({v['description']})" for k, v in DATASETS.items()
                        ) + " (default: selection)")
    parser.add_argument("--cleanup-all", action="store_true",
                        help="Drop ALL import_benchmark_* databases and exit")
    parser.add_argument("--timing", metavar="DBNAME",
                        help="Show pipeline timing from an existing test database and exit")
    parser.add_argument("--repeated-calls", metavar="DBNAME",
                        help="Replay each child command in one session on an existing test database, record first vs last call, and exit")
    parser.add_argument("--debug", action="store_true", default=True,
                        help="Enable debug logging in worker (default: true)")
    parser.add_argument("--no-debug", action="store_true",
                        help="Disable debug logging in worker")
    args = parser.parse_args()

    if args.cleanup_all:
        drop_all_test_databases()
        sys.exit(0)

    if args.list:
        list_test_databases()
        sys.exit(0)

    if args.timing:
        TEST_DB = args.timing
        show_timing(args.timing)
        sys.exit(0)

    if args.repeated_calls:
        TEST_DB = args.repeated_calls
        sys.exit(0 if run_repeated_call_benchmarks() else 1)

    log_print(f"{BLUE}Log file: {LOG_FILE}{NC}")

    if not args.skip_setup:
        create_isolated_db()
        atexit.register(lambda: drop_isolated_db(force=args.cleanup))
        setup_test_data(args.dataset)
    else:
        env = pg_env()
        TEST_DB = env.get("PGDATABASE", "statbus")
        log_print(f"Using existing database: {TEST_DB}")

    debug = not args.no_debug
    success = run_concurrent_test(timeout_seconds=args.timeout, debug=debug)
    sys.exit(0 if success else 1)
