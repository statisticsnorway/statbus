#!/usr/bin/env python3
"""
Benchmark the BRREG import through the real worker, in an isolated database.

1. Creates an isolated DB from the test template (POSTGRES_TEST_DB or statbus_test_template)
2. Loads the dataset with its loader script (samples/norway/brreg/), the same
   script ./cloud.sh import runs on an installation
3. Runs the real worker binary with --stop-when-idle
4. Reports the time per command, checks counts, records benchmarks, and replays
   each child command repeatedly to catch plans that degrade after the 5th call

Run with: ./test/import_benchmark.sh [--dataset selection|downloads|mixed] [-t TIMEOUT]
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
import json
import hashlib
import re
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

try:
    import psycopg2
    import psycopg2.extras
    from psycopg2 import sql
except ModuleNotFoundError:
    # Offline reporting/unit tests use only the standard library.
    psycopg2 = None

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
LAST_WORKER_RUN = {}
LAST_LOAD_RUN = {}


def calendar_date(value):
    """Require the loader's literal ISO date, including a real Gregorian day."""
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise argparse.ArgumentTypeError("must be a calendar date in YYYY-MM-DD form")
    try:
        date.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError("must be a valid calendar date in years 0001..9999") from None
    return value


def calendar_year(value):
    """Normalize a Gregorian year to the loader's four-digit YYYY contract."""
    if not re.fullmatch(r"[0-9]{1,4}", value) or not 1 <= int(value) <= 9999:
        raise argparse.ArgumentTypeError("must be a year in 1..9999")
    return f"{int(value):04d}"


def positive_int(value):
    """Acceptance thresholds describe at least one executing processing leaf."""
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("must be an integer >= 1") from None
    if number < 1:
        raise argparse.ArgumentTypeError("must be an integer >= 1")
    return number


def interval_summary(intervals):
    """Sweep durable half-open [start, stop) handler intervals, not samples.

    Stops at a timestamp take effect before starts at that timestamp. Missing
    endpoints cannot prove execution overlap and are reported separately.
    """
    events = {}
    complete = incomplete = 0
    for start, stop in intervals:
        if start is None or stop is None:
            incomplete += 1
            continue
        if stop < start:
            raise ValueError("process_stop_at precedes process_start_at")
        complete += 1
        if stop == start:
            continue
        events[start] = events.get(start, 0) + 1
        events[stop] = events.get(stop, 0) - 1
    active = peak = 0
    previous = None
    histogram = {}
    for at, delta in sorted(events.items()):
        if previous is not None and at > previous:
            seconds = (at - previous).total_seconds()
            histogram[active] = histogram.get(active, 0.0) + seconds
            peak = max(peak, active)
        active += delta
        previous = at
    points = sorted(events)
    return {
        "evidence": "durable_process_intervals",
        "interval_semantics": "[process_start_at, process_stop_at)",
        "complete_intervals": complete,
        "incomplete_intervals": incomplete,
        "max_concurrent_processing_leaves": peak,
        "overlap_seconds": sum(seconds for count, seconds in histogram.items() if count >= 2),
        "seconds_by_concurrency": {str(count): seconds for count, seconds in sorted(histogram.items())},
        "span_seconds": (points[-1] - points[0]).total_seconds() if points else 0.0,
    }


def phase_summary(job, phase):
    start, stop = job[f"{phase}_start_at"], job[f"{phase}_stop_at"]
    if start is not None and stop is not None and stop < start:
        raise ValueError(f"Job {job['id']} {phase} stop precedes start")
    return {"start_at": start, "stop_at": stop,
            "duration_seconds": (stop - start).total_seconds() if start is not None and stop is not None else None}


def summarize_jobs(jobs, leaves):
    """Keep job identity and phase chronology separate from global overlap."""
    results = []
    for job in jobs:
        row = dict(job)
        for phase in ("analysis", "processing"):
            row[phase] = phase_summary(job, phase)
        job_leaves = [leaf for leaf in leaves if str(leaf["job_id"]) == str(job["id"])]
        row["processing_leaves"] = job_leaves
        row["processing_overlap"] = interval_summary(
            (leaf["process_start_at"], leaf["process_stop_at"]) for leaf in job_leaves)
        results.append(row)
    return results


def json_value(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    raise TypeError(f"Cannot serialize {type(value).__name__}")


def write_result(path, result):
    """Publish a complete JSON document atomically, including failed runs."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(result, default=json_value, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def concurrency_acceptance(observation, minimum):
    actual = observation["max_concurrent_processing_leaves"]
    passed = minimum is None or actual >= minimum
    return {"required_minimum": minimum, "observed_actual": actual, "passed": passed,
            "evidence": "durable_process_intervals"}


def measured_imports(dataset, jobs, leaves):
    """Fixture SQL execution is not evidence of measured Crystal execution."""
    if dataset != "mixed":
        return jobs, leaves
    jobs = [job for job in jobs if job["slug"] in
            ("import_mixed_lu", "import_mixed_es", "import_mixed_informal")]
    measured_ids = {str(job["id"]) for job in jobs}
    return jobs, [leaf for leaf in leaves if str(leaf["job_id"]) in measured_ids]


def collect_observation(dataset="selection"):
    """Read actual configuration and durable evidence before plan replays."""
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT queue, default_concurrency FROM worker.queue_registry ORDER BY queue")
            queues = [dict(row) for row in cur.fetchall()]
            cur.execute("SELECT state::text, count(*) AS count FROM worker.tasks GROUP BY state ORDER BY state")
            task_states = {row["state"]: row["count"] for row in cur.fetchall()}
            cur.execute("""SELECT min(process_start_at) AS start_at, max(process_stop_at) AS stop_at,
                                  extract(epoch FROM max(process_stop_at)-min(process_start_at)) AS span_seconds
                             FROM worker.tasks""")
            span = dict(cur.fetchone())
            cur.execute("""SELECT t.id, t.payload->>'job_id' AS job_id, t.state::text,
                                  t.process_start_at, t.process_stop_at, t.process_duration_ms
                             FROM worker.tasks AS t
                            WHERE t.command = 'import_job_process_batch'
                              AND NOT EXISTS (SELECT 1 FROM worker.tasks AS child WHERE child.parent_id = t.id)
                            ORDER BY t.process_start_at NULLS LAST, t.id""")
            leaves = [dict(row) for row in cur.fetchall()]
            cur.execute("""SELECT id, slug, state::text, total_rows, imported_rows, error_count, warning_count,
                                  analysis_start_at, analysis_stop_at, processing_start_at, processing_stop_at,
                                  data_table_name, error, default_valid_from
                             FROM public.import_job ORDER BY id""")
            jobs = [dict(row) for row in cur.fetchall()]
            jobs, leaves = measured_imports(dataset, jobs, leaves)
            for job in jobs:
                cur.execute(sql.SQL("SELECT state::text, count(*) AS count FROM public.{} GROUP BY state ORDER BY state")
                            .format(sql.Identifier(job["data_table_name"])))
                counts = {row["state"]: row["count"] for row in cur.fetchall()}
                job["actual_data_rows"] = {"total": sum(counts.values()), "by_state": counts,
                                           "processed": counts.get("processed", 0), "error": counts.get("error", 0)}
        return {"queue_registry": queues,
                "configured_environment_overrides": {key: os.environ[key] for key in
                    ("WORKER_QUEUE_CONCURRENCY", "WORKER_DEFAULT_CONCURRENCY") if key in os.environ},
                "task_states": task_states, "failed_task_count": task_states.get("failed", 0),
                "worker_task_span": span, "jobs": summarize_jobs(jobs, leaves),
                "processing_overlap": interval_summary(
                    (leaf["process_start_at"], leaf["process_stop_at"]) for leaf in leaves)}
    finally:
        conn.close()


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
    if psycopg2 is None:
        raise RuntimeError("psycopg2 is required for database runs. Use ./test/import_benchmark.sh")
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
    "mixed": {
        "description": "Bounded synthetic mixed LU/formal ES/informal ES histories (3200 measured rows)",
        "setup_sql": "test/import_benchmark_mixed.sql",
        "check_sql": "test/import_benchmark_mixed_check.sql",
    },
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
            "tmp/roller_legal_relationships.csv",
        ],
        "optional_files": ["tmp/roller_legal_relationships.csv"],
        "slug_like": "import_%_2025",
    },
}


def source_metadata(dataset):
    """Record exact loader input bytes and optional-input absence for run provenance."""
    sources = []
    ds = DATASETS[dataset]
    for relative in ds.get("files", []):
        path = WORKSPACE / relative
        optional = relative in ds.get("optional_files", [])
        if optional and not path.exists():
            sources.append({"path": relative, "present": False, "size_bytes": None, "sha256": None})
            continue
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        sources.append({"path": relative, "present": True, "size_bytes": path.stat().st_size,
                        "sha256": digest.hexdigest()})
    return sources


def setup_test_data(dataset="selection", valid_from=None, year=None):
    """Load the dataset through its loader script, the same one ./cloud.sh
    import runs on an installation, into this run's isolated database."""
    global LAST_LOAD_RUN
    ds = DATASETS[dataset]
    if "setup_sql" in ds:
        run_psql_file(ds["setup_sql"])
        return

    log_print(f"\n{BLUE}Setting up test data: {ds['description']}...{NC}")

    for path in ds["files"]:
        full_path = WORKSPACE / path
        if not full_path.exists():
            if path in ds.get("optional_files", []):
                log_print(f"  Optional source absent: {path}")
                continue
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
    loader_args = [str(WORKSPACE / ds["loader"]), "--database", TEST_DB]
    if valid_from is not None:
        loader_args.extend(["--valid-from", valid_from])
    elif year is not None:
        loader_args.extend(["--year", year])
    LAST_LOAD_RUN = {"start_at": datetime.now(timezone.utc)}
    try:
        result = subprocess.run(
            loader_args,
            cwd=WORKSPACE, env=env, text=True, capture_output=True,
        )
    finally:
        LAST_LOAD_RUN["stop_at"] = datetime.now(timezone.utc)
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
    started_at = datetime.now(timezone.utc)
    start = time.monotonic()

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

    elapsed = time.monotonic() - start
    LAST_WORKER_RUN.clear()
    LAST_WORKER_RUN.update(start_at=started_at, stop_at=datetime.now(timezone.utc),
                           wall_seconds=elapsed, returncode=proc.returncode, timed_out=timed_out)

    if timed_out:
        log_print(f"\n{RED}Worker KILLED after {elapsed:.1f}s (timeout: {timeout_seconds}s){NC}")
    else:
        log_print(f"\n{BLUE}Worker exited with code {proc.returncode} in {elapsed:.1f}s{NC}")
    return proc.returncode, output_lines, elapsed


def check_dataset(dataset):
    """Run dataset-specific positive assertions with psql's fail-fast contract."""
    check_sql = DATASETS[dataset].get("check_sql")
    if check_sql is None:
        return {"status": "not_applicable", "passed": True}
    try:
        output = run_psql_file(check_sql)
        return {"status": "passed", "passed": True, "sql_file": check_sql, "summary": output.strip()}
    except Exception as error:
        return {"status": "failed", "passed": False, "sql_file": check_sql, "error": str(error)}


def run_concurrent_test(timeout_seconds=300, debug=True, result=None, require_import_concurrency=None,
                        dataset="selection"):
    """Run the real Crystal worker and verify results."""
    log_print(f"\n{'='*60}")
    log_print(f"  Concurrent Worker Test (real Crystal worker)")
    log_print(f"  Database: {TEST_DB}")
    log_print(f"  Timeout: {timeout_seconds}s")
    log_print(f"  Log: {LOG_FILE}")
    log_print(f"{'='*60}")

    returncode, output, elapsed = run_worker(TEST_DB, timeout_seconds, debug)
    if result is None:
        result = {}
    result["worker"] = dict(LAST_WORKER_RUN)
    observation = collect_observation(dataset)
    result.update(observation)
    acceptance = concurrency_acceptance(observation["processing_overlap"], require_import_concurrency)
    result["import_concurrency_acceptance"] = acceptance
    log_print(f"\n  Proven processing leaf concurrency: {acceptance['observed_actual']} "
              f"(durable handler intervals)")
    if not acceptance["passed"]:
        log_print(f"{RED}  Import concurrency requirement unmet: required >= "
                  f"{require_import_concurrency}, observed {acceptance['observed_actual']}{NC}", "error")

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

    # Record the dataset's domain assertions before optional diagnostic replays.
    dataset_check = check_dataset(dataset)
    result.setdefault("checks", {})["dataset"] = dataset_check
    if not dataset_check["passed"]:
        log_print(f"{RED}  Dataset check failed: {dataset_check.get('error')}{NC}", "error")

    # Concurrency-corruption gate — three layers
    consistent, consistency_summary = check_consistency()

    # Run hierarchy function benchmarks (after analytics pipeline is complete)
    if not failed:
        run_hierarchy_benchmarks()

    plans_stable = run_repeated_call_benchmarks() if not failed else True

    result["checks"] = {"dataset": dataset_check,
                        "consistency": {"passed": consistent, "summary": consistency_summary},
                        "repeated_call_plans_stable": plans_stable}
    success = (returncode == 0 and not LAST_WORKER_RUN.get("timed_out", False)
               and not failed and consistent and plans_stable and acceptance["passed"] and dataset_check["passed"])
    result["success"] = success
    if success:
        log_print(f"\n{GREEN}{'='*60}")
        log_print(f"  SUCCESS: Worker processed all tasks in {elapsed:.1f}s; counts consistent")
        log_print(f"{'='*60}{NC}")
    else:
        log_print(f"\n{RED}{'='*60}")
        log_print(f"  FAILED: returncode={returncode}, failed_tasks={observation['failed_task_count']}, "
                  f"consistent={consistent}, concurrency_met={acceptance['passed']}")
        if not consistent:
            log_print(f"  {consistency_summary}", "error")
        log_print(f"{'='*60}{NC}")
    return success


def check_consistency():
    """Verify post-run statistical_history is internally and externally consistent.

    Three layers of check (STATBUS-558: the history table is a sparse delta table,
    statistical_history and statistical_history_facet are views over it):
      A. Incremental == rebuild: the stored statistical_history_facet_delta rows,
         maintained cycle by cycle, equal a full rebuild from statistical_unit
         (computed in a rolled-back transaction), every column and unit_ids included.
         Stats compare as the net (in - out) of every numeric field and category
         count per variable, which is what a row adds to the stock. Fails when a
         cycle staged a wrong delta or missed one.
      B. Ground-truth: sh.exists_count == COUNT(DISTINCT unit_id) from
         statistical_unit at the corresponding year-end. Catches stale rows.
      C. Staging drained: no staged delta row is left after the last reduce.

    Returns (consistent: bool, summary: str). Logs detail per layer.
    """
    log_print(f"\n  {BLUE}Consistency checks:{NC}")

    # The net (in - out) of every numeric field and category count of a stats delta, as text.
    # The gross in and out depend on the path of changes; the net is what the row adds to the stock.
    stats_net_sql = """
        CREATE FUNCTION pg_temp.stats_net(d jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $stats_net$
            SELECT string_agg(x.key || '.' || x.field || '=' || x.net, ',' ORDER BY x.key, x.field)
            FROM (SELECT e.key, f.field,
                         COALESCE((e.value->'in'->>f.field)::numeric, 0) - COALESCE((e.value->'out'->>f.field)::numeric, 0) AS net
                  FROM jsonb_each(COALESCE(d, '{}') - 'type'::text) AS e
                  CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in', '{}') || COALESCE(e.value->'out', '{}')) AS field) AS f
                  WHERE jsonb_typeof(COALESCE(e.value->'in'->f.field, e.value->'out'->f.field)) = 'number'
                  UNION ALL
                  SELECT e.key, f.field || '.' || c.k,
                         COALESCE((e.value->'in'->f.field->>c.k)::numeric, 0) - COALESCE((e.value->'out'->f.field->>c.k)::numeric, 0)
                  FROM jsonb_each(COALESCE(d, '{}') - 'type'::text) AS e
                  CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in', '{}') || COALESCE(e.value->'out', '{}')) AS field) AS f
                  CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in'->f.field, '{}') || COALESCE(e.value->'out'->f.field, '{}')) AS k
                                      WHERE jsonb_typeof(COALESCE(e.value->'in'->f.field, e.value->'out'->f.field)) = 'object') AS c) AS x
            WHERE x.net <> 0
        $stats_net$
    """

    rows_sql = """
        SELECT unit_type::text, primary_activity_category_path::text, secondary_activity_category_path::text,
               sector_path::text, legal_form_id, physical_region_path::text, physical_country_id, unit_size_id,
               status_id, on_month::text,
               concat_ws('|', exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
                         exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
                         births, deaths, name_change_count, primary_activity_category_change_count,
                         secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
                         physical_region_change_count, physical_country_change_count, physical_address_change_count,
                         unit_size_change_count, status_change_count) AS counts,
               pg_temp.stats_net(stats_delta) AS stats, pg_temp.stats_net(stats_ended_month) AS stats_ended_month,
               pg_temp.stats_net(stats_ended_year) AS stats_ended_year, unit_ids::text
          FROM public.statistical_history_facet_delta
    """

    conn = get_conn()
    # Layer A empties and rebuilds the live delta table, then rolls back: it must run inside one
    # transaction, whatever the connection default.
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("SET ROLE postgres")  # the staging table has no grants for API roles

            # --- Layer C: staging drained ---
            cur.execute("SELECT count(*) FROM public.statistical_history_facet_delta_staging")
            orphan_count = cur.fetchone()[0]

            # --- Layer A: incremental == rebuild (rolled back) ---
            cur.execute(stats_net_sql)
            cur.execute(f"CREATE TEMP TABLE bench_incremental AS {rows_sql}")
            cur.execute("""
                TRUNCATE public.statistical_history_facet_delta, public.statistical_history_facet_delta_staging
            """)
            cur.execute("CALL worker.statistical_history_facet_delta_stage_partition('[0,16384)'::int4range, true)")
            cur.execute("CALL worker.statistical_history_facet_delta_apply()")
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

def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Test concurrent worker processing with isolated database",
        epilog="Databases are RETAINED by default for comparison. Use --cleanup to delete."
    )
    parser.add_argument("-t", "--timeout", type=int, default=600,
                        help="Worker timeout in seconds (default: 600)")
    validity = parser.add_mutually_exclusive_group()
    validity.add_argument("--valid-from", type=calendar_date, metavar="YYYY-MM-DD",
                          help="Forward an explicit validity date to the BRREG loader")
    validity.add_argument("--year", type=calendar_year, metavar="YYYY",
                          help="Forward a year (1..9999) to the BRREG loader as YYYY")
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
    parser.add_argument("--result-json", type=Path, metavar="PATH",
                        help="Write machine-readable run evidence, including failures, to PATH")
    parser.add_argument("--require-import-concurrency", type=positive_int, metavar="MIN",
                        help="Acceptance assertion only: require MIN concurrent processing leaves proven by durable intervals (>=1). Does not change queue configuration")
    args = parser.parse_args(argv)
    if (args.valid_from is not None or args.year is not None) and (
            args.dataset == "mixed" or args.skip_setup or args.list or args.cleanup_all
            or args.timing or args.repeated_calls):
        parser.error("--valid-from and --year require a selection/downloads worker run with setup")
    if (args.result_json is not None or args.require_import_concurrency is not None) and (
            args.list or args.cleanup_all or args.timing or args.repeated_calls):
        parser.error("--result-json and --require-import-concurrency require a worker benchmark run")
    return args


def main(argv=None):
    global TEST_DB, LAST_LOAD_RUN
    args = parse_args(argv)
    LAST_LOAD_RUN = {}

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

    result = {"schema_version": 1, "success": False, "dataset": args.dataset,
              "requested_validity": {"valid_from": args.valid_from, "year": args.year},
              "checks": {"dataset": {"status": "not_run", "passed": False}},
              "timeout_seconds": args.timeout, "log_file": str(LOG_FILE)}
    try:
        if not args.skip_setup:
            create_isolated_db()
            atexit.register(lambda: drop_isolated_db(force=args.cleanup))
            if args.result_json is not None:
                result["source_files"] = source_metadata(args.dataset)
            if args.valid_from is not None or args.year is not None:
                setup_test_data(args.dataset, valid_from=args.valid_from, year=args.year)
            else:
                setup_test_data(args.dataset)
        else:
            env = pg_env()
            TEST_DB = env.get("PGDATABASE", "statbus")
            log_print(f"Using existing database: {TEST_DB}")

        success = run_concurrent_test(timeout_seconds=args.timeout, debug=not args.no_debug,
                                      result=result, require_import_concurrency=args.require_import_concurrency, dataset=args.dataset)
        return 0 if success else 1
    except Exception as error:
        result["error"] = {"type": type(error).__name__, "message": str(error)}
        log_print(f"{RED}Benchmark failed: {error}{NC}", "error")
        return 1
    finally:
        if LAST_LOAD_RUN:
            result["load"] = dict(LAST_LOAD_RUN)
        result["database"] = TEST_DB
        if args.result_json is not None:
            write_result(args.result_json, result)


if __name__ == "__main__":
    sys.exit(main())
