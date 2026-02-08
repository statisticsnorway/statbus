#!/usr/bin/env python3
"""
Test concurrent worker processing with isolated database.

1. Creates isolated DB from template_statbus_migrated
2. Loads test data (like test 401) via psql
3. Runs N threads calling worker.process_tasks()
4. Reports deadlock/serialization errors
5. Retains database by default for comparison across runs

Run with: ./test/test_concurrent_worker.sh [-n THREADS] [-t TASKS]
"""

import os
import sys
import time
import subprocess
import argparse
import atexit
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import psycopg2
from psycopg2 import errors as pg_errors

# ============================================================================
# Configuration
# ============================================================================

WORKSPACE = Path(__file__).parent.parent.absolute()
TEMPLATE_DB = "template_statbus_migrated"
MANAGE = str(WORKSPACE / "devops" / "manage-statbus.sh")

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
# Concurrent Worker Simulation
# ============================================================================

def worker_thread(thread_id, max_tasks):
    """Simulate a worker fiber: own connection, calls process_tasks in a loop"""
    result = {"thread_id": thread_id, "tasks": 0, "errors": [], "elapsed": 0}
    start = time.time()

    log.info(f"Thread {thread_id}: starting (max_tasks={max_tasks or 'unlimited'})")

    try:
        conn = get_conn()
        conn.autocommit = True  # Each CALL is its own transaction

        idle_count = 0
        iteration = 0
        while max_tasks == 0 or iteration < max_tasks:
            iteration += 1
            try:
                with conn.cursor() as cur:
                    # Check if there are actionable tasks
                    cur.execute("""
                        SELECT count(*) FROM worker.tasks
                        WHERE state IN ('pending', 'processing', 'waiting')
                    """)
                    actionable = cur.fetchone()[0]

                    if actionable == 0:
                        idle_count += 1
                        if idle_count >= 5:
                            log.info(f"Thread {thread_id}: no more work after {result['tasks']} tasks")
                            break
                        time.sleep(1)
                        continue

                    idle_count = 0
                    call_start = time.time()
                    cur.execute("CALL worker.process_tasks(p_batch_size := 1)")
                    call_ms = (time.time() - call_start) * 1000
                    result["tasks"] += 1

                    # If process_tasks returned very quickly (<100ms), it likely
                    # found no claimable work (another thread has it). Back off
                    # to avoid spin-looping that can crash PostgreSQL.
                    if call_ms < 100:
                        time.sleep(0.2)

                    if result["tasks"] % 10 == 0:
                        log.info(f"Thread {thread_id}: processed {result['tasks']} tasks ({actionable} actionable)")

            except pg_errors.DeadlockDetected as e:
                msg = f"DEADLOCK: {e.pgerror}"
                result["errors"].append(msg)
                log.error(f"Thread {thread_id}: {msg}")
                # Don't break - retry like the real worker would
                time.sleep(0.1)
            except pg_errors.SerializationFailure as e:
                msg = f"SERIALIZATION: {e.pgerror}"
                result["errors"].append(msg)
                log.error(f"Thread {thread_id}: {msg}")
                time.sleep(0.1)
            except psycopg2.Error as e:
                msg = f"DB ERROR ({e.pgcode}): {e.pgerror}"
                result["errors"].append(msg)
                log.error(f"Thread {thread_id}: {msg}")
                # Reconnect on connection-level errors
                try:
                    conn.close()
                except Exception:
                    pass
                try:
                    conn = get_conn()
                    conn.autocommit = True
                except Exception:
                    break

        conn.close()
    except Exception as e:
        msg = f"CONNECTION ERROR: {e}"
        result["errors"].append(msg)
        log.error(f"Thread {thread_id}: {msg}")

    result["elapsed"] = time.time() - start
    log.info(f"Thread {thread_id}: finished in {result['elapsed']:.1f}s, {result['tasks']} tasks, {len(result['errors'])} errors")
    return result


def run_concurrent_test(num_threads, tasks_per_thread):
    """Run concurrent worker test"""
    log_print(f"\n{'='*60}")
    log_print(f"  Concurrent Worker Test")
    log_print(f"  Database: {TEST_DB}")
    log_print(f"  Threads: {num_threads}, Max tasks/thread: {tasks_per_thread}")
    log_print(f"  Log: {LOG_FILE}")
    log_print(f"{'='*60}")

    start = time.time()

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = {
            executor.submit(worker_thread, i, tasks_per_thread): i
            for i in range(num_threads)
        }

        results = []
        for future in as_completed(futures):
            r = future.result()
            results.append(r)
            status = f"{GREEN}OK{NC}" if not r["errors"] else f"{RED}{len(r['errors'])} errors{NC}"
            log_print(f"  Thread {r['thread_id']}: {r['tasks']} tasks, {r['elapsed']:.1f}s [{status}]")

    elapsed = time.time() - start

    # Summary
    total_tasks = sum(r["tasks"] for r in results)
    all_errors = []
    for r in results:
        all_errors.extend(r["errors"])

    log_print(f"\n{'='*60}")
    log_print(f"  Database: {TEST_DB}")
    log_print(f"  Total time: {elapsed:.1f}s")
    log_print(f"  Total tasks processed: {total_tasks}")
    log_print(f"  Total errors: {len(all_errors)}")

    # Final task state (retry connection in case DB is recovering)
    for attempt in range(10):
        try:
            conn = get_conn()
            break
        except Exception as e:
            if attempt < 9:
                log_print(f"  {YELLOW}DB connection attempt {attempt+1}/10 failed, retrying in 5s...{NC}")
                time.sleep(5)
            else:
                log_print(f"  {RED}Could not connect to DB for summary: {e}{NC}", "error")
                return False
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

    # Consider both thread-level errors AND DB-level failed tasks
    has_thread_errors = len(all_errors) > 0
    has_failed_tasks = len(failed) > 0 if failed else False

    if has_thread_errors or has_failed_tasks:
        log_print(f"\n{RED}{'='*60}")
        if has_thread_errors:
            log_print(f"  THREAD ERRORS: {len(all_errors)}")
            unique = set()
            for e in all_errors:
                first_line = e.split('\n')[0]
                if first_line not in unique:
                    unique.add(first_line)
                    log_print(f"    {first_line}", "error")
        if has_failed_tasks:
            log_print(f"  FAILED TASKS: {len(failed)} (see above)")
        log_print(f"{'='*60}{NC}")
        return False
    else:
        log_print(f"\n{GREEN}{'='*60}")
        log_print(f"  SUCCESS: All {num_threads} threads completed, 0 failed tasks")
        log_print(f"{'='*60}{NC}")
        return True


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
    parser.add_argument("-n", "--threads", type=int, default=4,
                        help="Number of concurrent threads (default: 4)")
    parser.add_argument("-t", "--tasks", type=int, default=0,
                        help="Max process_tasks calls per thread (0=unlimited, default: 0)")
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

    success = run_concurrent_test(args.threads, args.tasks)
    sys.exit(0 if success else 1)
