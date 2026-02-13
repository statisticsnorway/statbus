#!/usr/bin/env python3
"""
Test concurrent worker processing with isolated database.

1. Creates isolated DB from template_statbus_migrated
2. Loads test data (like test 401) via psql
3. Runs the real Crystal worker binary with --stop-when-idle
4. Reports results from worker stdout and final task states

Run with: ./test/test_concurrent_worker.sh [-t TIMEOUT]
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

# ============================================================================
# Configuration
# ============================================================================

WORKSPACE = Path(__file__).parent.parent.absolute()
TEMPLATE_DB = "template_statbus_migrated"
MANAGE = str(WORKSPACE / "devops" / "manage-statbus.sh")
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
    LOG_FILE = tmp_dir / f"test_concurrent_{os.getpid()}.log"

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
    """Get PostgreSQL connection env vars by evaluating manage-statbus.sh postgres-variables"""
    result = subprocess.run(
        [MANAGE, "postgres-variables"],
        capture_output=True, text=True, cwd=WORKSPACE
    )
    if result.returncode != 0:
        raise Exception(f"Failed to get postgres-variables: {result.stderr}")

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
    """Create a psycopg2 connection using the same credentials as manage-statbus.sh psql"""
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
    """Run SQL via manage-statbus.sh psql"""
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
    """Run SQL file via manage-statbus.sh psql"""
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
    TEST_DB = f"test_concurrent_{os.getpid()}"

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
        log_print(f"  Delete:  {MANAGE} psql -d postgres -c 'DROP DATABASE \"{TEST_DB}\"'")
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
    """Drop ALL test_concurrent_* databases"""
    conn = get_conn(dbname="postgres")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("""
            SELECT datname FROM pg_database
            WHERE datname LIKE 'test_concurrent_%'
            ORDER BY datname
        """)
        dbs = [row[0] for row in cur.fetchall()]

        if not dbs:
            log_print("No test_concurrent_* databases found.")
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
        "definition_year": "2024",
        "lu_slug": "import_hovedenhet_concurrent",
        "es_slug": "import_underenhet_concurrent",
        "lu_csv": "samples/norway/legal_unit/enheter-selection.csv",
        "es_csv": "samples/norway/establishment/underenheter-selection.csv",
    },
    "downloads": {
        "description": "BRREG full downloads (~1M rows, like test 403)",
        "definition_year": "2025",
        "lu_slug": "import_hovedenhet_2025",
        "es_slug": "import_underenhet_2025",
        "lu_csv": "tmp/enheter.csv",
        "es_csv": "tmp/underenheter_filtered.csv",
    },
}


def setup_test_data(dataset="selection"):
    """Setup test data from the specified dataset."""
    ds = DATASETS[dataset]
    year = ds["definition_year"]

    log_print(f"\n{BLUE}Setting up test data: {ds['description']}...{NC}")

    # Check that CSV files exist
    for label, path in [("LU", ds["lu_csv"]), ("ES", ds["es_csv"])]:
        full_path = WORKSPACE / path
        if not full_path.exists():
            log_print(f"{RED}ERROR: {label} CSV not found: {full_path}{NC}", "error")
            if dataset == "downloads":
                log_print(f"  Download from BRREG and place in tmp/", "error")
            sys.exit(1)
        size_mb = full_path.stat().st_size / (1024 * 1024)
        log_print(f"  {label} CSV: {path} ({size_mb:.1f} MB)")

    # Run setup files via psql
    log_print("  Running test/setup.sql...")
    run_psql_file("test/setup.sql")

    log_print("  Running samples/norway/getting-started.sql...")
    run_psql_file("samples/norway/getting-started.sql")

    log_print(f"  Running import definition for hovedenhet ({year})...")
    run_psql_file(f"samples/norway/brreg/create-import-definition-hovedenhet-{year}.sql")

    log_print(f"  Running import definition for underenhet ({year})...")
    run_psql_file(f"samples/norway/brreg/create-import-definition-underenhet-{year}.sql")

    # Create import jobs
    log_print("  Creating import jobs...")
    run_psql(f"""
BEGIN;

CALL test.set_user_from_email('test.admin@statbus.org');

-- Create LU import job (uploaded FIRST = higher priority)
WITH def_he AS (
  SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_{year}'
)
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, user_id)
SELECT def_he.id, '{ds["lu_slug"]}', '2025-01-01'::date, 'infinity'::date, 'Concurrent test LU',
       (SELECT id FROM public.user WHERE email = 'test.admin@statbus.org')
FROM def_he
ON CONFLICT (slug) DO NOTHING;

COMMIT;
""")

    # Load LU data FIRST (priority by upload order)
    log_print(f"  Loading LU CSV data ({ds['lu_csv']})...")
    run_psql(f"\\copy public.{ds['lu_slug']}_upload FROM '{ds['lu_csv']}' WITH CSV HEADER")

    # Create ES import job SECOND
    run_psql(f"""
BEGIN;

CALL test.set_user_from_email('test.admin@statbus.org');

-- Create ES import job (uploaded SECOND = lower priority)
WITH def_ue AS (
  SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_{year}'
)
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, user_id)
SELECT def_ue.id, '{ds["es_slug"]}', '2025-01-01'::date, 'infinity'::date, 'Concurrent test ES',
       (SELECT id FROM public.user WHERE email = 'test.admin@statbus.org')
FROM def_ue
ON CONFLICT (slug) DO NOTHING;

COMMIT;
""")

    # Load ES data SECOND
    log_print(f"  Loading ES CSV data ({ds['es_csv']})...")
    run_psql(f"\\copy public.{ds['es_slug']}_upload FROM '{ds['es_csv']}' WITH CSV HEADER")

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
            WHERE slug LIKE 'import_%_concurrent'
            ORDER BY slug
        """)
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
    conn.close()

    success = returncode == 0 and not failed
    if success:
        log_print(f"\n{GREEN}{'='*60}")
        log_print(f"  SUCCESS: Worker processed all tasks in {elapsed:.1f}s")
        log_print(f"{'='*60}{NC}")
    else:
        log_print(f"\n{RED}{'='*60}")
        log_print(f"  FAILED: returncode={returncode}, failed_tasks={len(failed)}")
        log_print(f"{'='*60}{NC}")
    return success


def list_test_databases():
    """List existing test databases"""
    conn = get_conn(dbname="postgres")
    with conn.cursor() as cur:
        cur.execute("""
            SELECT datname, pg_size_pretty(pg_database_size(datname))
            FROM pg_database
            WHERE datname LIKE 'test_concurrent_%'
            ORDER BY datname
        """)
        rows = cur.fetchall()
        if rows:
            print("Existing test databases:")
            for row in rows:
                print(f"  {row[0]} ({row[1]})")
        else:
            print("No test_concurrent_* databases found.")
    conn.close()


# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Test concurrent worker processing with isolated database",
        epilog="Databases are RETAINED by default for comparison. Use --cleanup to delete."
    )
    parser.add_argument("-t", "--timeout", type=int, default=300,
                        help="Worker timeout in seconds (default: 300)")
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
                        help="Drop ALL test_concurrent_* databases and exit")
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
