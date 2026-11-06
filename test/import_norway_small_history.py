#!/usr/bin/env python3
"""
Test script for importing Norway small history data through the REST API
This test replicates the functionality in test/sql/50_import_jobs_for_norway_small_history.sql
but uses the REST API instead of direct SQL connections.

Run with `./test/import_norway_small_history.sh [create|delete]` that uses venv.
  create: Set up and import Norway small history data (default)
  delete: Clean up by removing imported data and definitions

With --isolated, the run touches no shared database: it creates its own database from the test template
(import_norway_small_history_<pid>), starts its own PostgREST container on a free loopback port against
that database, imports through the REST API as usual, and runs the worker with --stop-when-idle in place of
the SSE status stream (which needs the app). The database is retained for inspection unless --cleanup.
"""

import os
import sys
import json
import time
import requests
import tempfile
import threading
import argparse
import subprocess
from queue import Queue, Empty
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any, Union

# Colors for output
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

# Determine workspace directory
WORKSPACE = Path(__file__).parent.parent.absolute()
os.chdir(WORKSPACE)

# Load environment variables from .env
def load_env_vars():
    env_file = WORKSPACE / ".env"
    if env_file.exists():
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                key, value = line.split('=', 1)
                os.environ[key] = value.strip('"')

# Configuration from environment variables
load_env_vars()
# Extract host and port from API_PUBLIC_URL
API_BASE_URL = os.environ.get("API_PUBLIC_URL", "http://127.0.0.1:3000")
# --isolated: the PostgREST container serves /rest/... at its root, so requests drop the /rest prefix.
REST_PREFIX_STRIP = False


def api_url(endpoint: str) -> str:
    """URL for an endpoint written as /rest/..., for Caddy (default) or a bare PostgREST (--isolated)."""
    if REST_PREFIX_STRIP and endpoint.startswith("/rest/"):
        return f"{API_BASE_URL}{endpoint[len('/rest'):]}"
    return f"{API_BASE_URL}{endpoint}"


# ============================================================================
# --isolated: own database, own PostgREST, worker run to idle
# ============================================================================

ISOLATED_DB: Optional[str] = None
ISOLATED_REST_CONTAINER: Optional[str] = None
TEMPLATE_DB = os.environ.get("POSTGRES_TEST_DB", "statbus_test_template")


def sb_psql(sql: str, dbname: str) -> str:
    """Run SQL through ./sb psql on dbname; fail on any error."""
    result = subprocess.run([str(WORKSPACE / "sb"), "psql", "-d", dbname, "-v", "ON_ERROR_STOP=1", "-At"],
                            input=sql, text=True, capture_output=True, cwd=WORKSPACE)
    if result.returncode != 0:
        raise RuntimeError(f"psql on {dbname} failed: {result.stderr.strip()}")
    return result.stdout


def free_loopback_port() -> int:
    import socket
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def isolated_setup() -> None:
    """Create the database from the template, load the JWT secret and test users, start PostgREST on it."""
    global ISOLATED_DB, ISOLATED_REST_CONTAINER, API_BASE_URL, REST_PREFIX_STRIP
    ISOLATED_DB = f"import_norway_small_history_{os.getpid()}"
    log_info(f"Creating isolated database {ISOLATED_DB} from {TEMPLATE_DB}")
    # Serialised with the benchmark and the test runner, which also open the template (same lock key).
    sb_psql(f"""SELECT pg_advisory_lock(59328);
ALTER DATABASE {TEMPLATE_DB} WITH ALLOW_CONNECTIONS = true;
CREATE DATABASE "{ISOLATED_DB}" WITH TEMPLATE {TEMPLATE_DB};
ALTER DATABASE {TEMPLATE_DB} WITH ALLOW_CONNECTIONS = false;
SELECT pg_advisory_unlock(59328);""", "postgres")
    jwt_secret = os.environ["JWT_SECRET"]
    slot = os.environ["DEPLOYMENT_SLOT_CODE"]
    sb_psql(f"""INSERT INTO auth.secrets (key, value, description) VALUES ('jwt_secret', '{jwt_secret}', 'JWT signing secret')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp();
ALTER DATABASE "{ISOLATED_DB}" SET app.settings.deployment_slot_code TO '{slot}';""", ISOLATED_DB)
    with open(WORKSPACE / "test" / "setup.sql") as f:
        sb_psql(f.read(), ISOLATED_DB)

    port = free_loopback_port()
    ISOLATED_REST_CONTAINER = f"statbus-nsh-rest-{os.getpid()}"
    network = f"{os.environ['COMPOSE_INSTANCE_NAME']}_default"
    env = {
        "PGRST_DB_URI": f"postgres://authenticator:{os.environ['POSTGRES_AUTHENTICATOR_PASSWORD']}@db:5432/{ISOLATED_DB}",
        "PGRST_DB_SCHEMAS": os.environ.get("PGRST_DB_SCHEMAS", "public"),
        "PGRST_DB_ANON_ROLE": "anon",
        "PGRST_DB_USE_LEGACY_GUCS": "false",
        "PGRST_JWT_SECRET": jwt_secret,
        "PGRST_APP_SETTINGS_ACCESS_JWT_EXP": os.environ["ACCESS_JWT_EXPIRY"],
        "PGRST_APP_SETTINGS_REFRESH_JWT_EXP": os.environ["REFRESH_JWT_EXPIRY"],
        "PGRST_DB_AGGREGATES_ENABLED": "true",
        "PGRST_JWT_AUD": "statbus",
        "PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE": slot,
        "PGRST_DB_CONFIG": "true",
        "PGRST_DB_PRE_REQUEST": "auth.check_api_key_revocation",
    }
    cmd = ["docker", "run", "-d", "--rm", "--name", ISOLATED_REST_CONTAINER, "--network", network,
           "-p", f"127.0.0.1:{port}:3000"]
    for key, value in env.items():
        cmd += ["-e", f"{key}={value}"]
    cmd += ["postgrest/postgrest:v14.14"]
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"Starting PostgREST failed: {result.stderr.strip()}")
    API_BASE_URL = f"http://127.0.0.1:{port}"
    REST_PREFIX_STRIP = True
    deadline = time.time() + 60
    while time.time() < deadline:
        try:
            if requests.get(api_url("/rest/rpc/auth_status"), timeout=2).status_code == 200:
                log_success(f"PostgREST {ISOLATED_REST_CONTAINER} serving {ISOLATED_DB} at {API_BASE_URL}")
                return
        except requests.RequestException:
            pass
        time.sleep(1)
    raise RuntimeError(f"PostgREST on {API_BASE_URL} did not become ready in 60 s")


def isolated_authorize(session: requests.Session) -> None:
    """Caddy turns the statbus cookie into a bearer token; a bare PostgREST needs the header itself."""
    token = session.cookies.get("statbus")
    if not token:
        raise RuntimeError("Login set no statbus cookie")
    session.headers["Authorization"] = f"Bearer {token}"


def isolated_run_worker(timeout_seconds: int = 1800) -> bool:
    """Run the worker on the isolated database until every queue is idle."""
    binary = WORKSPACE / "cli" / "bin" / "statbus"
    cmd = [str(binary), "worker", "--stop-when-idle", "--database", ISOLATED_DB]
    log_info(f"Running worker: {' '.join(cmd)}")
    start = time.time()
    result = subprocess.run(cmd, cwd=WORKSPACE, text=True, capture_output=True, timeout=timeout_seconds)
    log_info(f"Worker exited with code {result.returncode} after {time.time() - start:.1f} s")
    if result.returncode != 0:
        log_error(f"Worker failed:\n{result.stdout[-4000:]}\n{result.stderr[-4000:]}")
        return False
    failed = sb_psql("SELECT count(*) FROM worker.tasks WHERE state = 'failed';", ISOLATED_DB).strip()
    pending = sb_psql("""SELECT count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON c.command = t.command
WHERE c.queue <> 'maintenance' AND t.state IN ('pending', 'processing', 'waiting');""", ISOLATED_DB).strip()
    log_info(f"Tasks failed: {failed}, unfinished outside maintenance: {pending}")
    return failed == "0" and pending == "0"


def isolated_verify_history() -> bool:
    """The history views agree with statistical_unit at every year end (the import benchmark's check B)."""
    divergent = sb_psql("""
WITH years AS (SELECT DISTINCT year FROM public.statistical_history WHERE resolution = 'year')
SELECT y.year, sh.unit_type, sh.exists_count,
       (SELECT count(DISTINCT su.unit_id) FROM public.statistical_unit AS su
         WHERE su.unit_type = sh.unit_type
           AND su.valid_from <= make_date(y.year, 12, 31) AND make_date(y.year, 12, 31) < su.valid_until
           AND COALESCE(su.birth_date, su.valid_from) <= make_date(y.year, 12, 31)
           AND (su.death_date IS NULL OR make_date(y.year, 12, 31) < su.death_date)) AS truth
FROM years AS y JOIN public.statistical_history AS sh ON sh.resolution = 'year' AND sh.year = y.year;""",
                        ISOLATED_DB)
    rows = [line.split("|") for line in divergent.strip().splitlines() if line]
    bad = [r for r in rows if r[2] != r[3]]
    log_info(f"History year rows checked against statistical_unit: {len(rows)}, divergent: {len(bad)}")
    for r in bad[:10]:
        log_error(f"  year {r[0]} {r[1]}: history {r[2]}, statistical_unit {r[3]}")
    return len(rows) > 0 and not bad


def isolated_teardown(drop_db: bool) -> None:
    if ISOLATED_REST_CONTAINER:
        subprocess.run(["docker", "rm", "-f", ISOLATED_REST_CONTAINER], capture_output=True)
    if ISOLATED_DB and drop_db:
        sb_psql(f'DROP DATABASE IF EXISTS "{ISOLATED_DB}" WITH (FORCE);', "postgres")
        log_info(f"Dropped {ISOLATED_DB}")
    elif ISOLATED_DB:
        log_info(f"Database retained: {ISOLATED_DB} (inspect with ./sb psql -d {ISOLATED_DB})")

# Test users from setup.sql
ADMIN_EMAIL = "test.admin@statbus.org"
ADMIN_PASSWORD = "Admin#123!"
REGULAR_EMAIL = "test.regular@statbus.org"
REGULAR_PASSWORD = "Regular#123!"

# Helper functions
def log_success(message: str) -> None:
    """Print a success message"""
    print(f"{GREEN}✓ {message}{NC}")

def log_error(message: str, debug_info_fn=None) -> None:
    """Print an error message and exit
    
    Args:
        message: The error message to display
        debug_info_fn: Optional function to call for additional debug info before exit
    """
    print(f"{RED}✗ {message}{NC}")
    
    # Call the debug info function if provided
    if debug_info_fn and callable(debug_info_fn):
        try:
            debug_info_fn()
        except Exception as e:
            print(f"{RED}Error while printing debug info: {e}{NC}")
    
    sys.exit(1)

def log_info(message: str) -> None:
    """Print an info message"""
    print(f"{BLUE}{message}{NC}")

def log_warning(message: str) -> None:
    """Print a warning message"""
    print(f"{YELLOW}{message}{NC}")

def debug_info(message: str) -> None:
    """Print debug information if DEBUG is set"""
    if os.environ.get("DEBUG"):
        print(f"{YELLOW}DEBUG: {message}{NC}")

def api_login(session: requests.Session, email: str, password: str) -> Optional[int]:
    """Login to the API and return user ID if successful"""
    log_info(f"Logging in as {email}...")
    
    try:
        response = session.post(
            api_url("/rest/rpc/login"),
            json={"email": email, "password": password},
            headers={"Content-Type": "application/json"}
        )
        
        debug_info(f"Login response status code: {response.status_code}")
        
        if response.status_code != 200:
            def print_response_debug_info():
                print(f"Response body: {response.text}")
                print(f"API endpoint: {API_BASE_URL}/rest/rpc/login")
                print(f"Attempted credentials: Email={email}, Password={'*' * len(password)}")
                print(f"Server URL: {API_BASE_URL}")
            
            log_error(f"API login failed for {email}. Status code: {response.status_code}", print_response_debug_info)
            return None
        
        data = response.json()
        debug_info(f"Login response: {json.dumps(data, indent=2)}")
        
        if data.get("uid") is not None:
            log_success(f"API login successful for {email}")
            return data.get("uid")
        else:
            def print_login_failure_details():
                print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
                print(f"{RED}API endpoint: {API_BASE_URL}/rest/rpc/login{NC}")
                print(f"{RED}Attempted credentials: Email={email}, Password={'*' * len(password)}{NC}")
                print(f"{RED}Server URL: {API_BASE_URL}{NC}")
                print(f"{RED}Note: Empty/null response values indicate authentication failed{NC}")
            
            log_error(f"API login failed for {email} - received empty user data.", print_login_failure_details)
            return None
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
        return None
    except json.JSONDecodeError as e:
        log_error(f"Invalid JSON response from server: {e}")
        return None


def api_request(session: requests.Session, method: str, endpoint: str, 
                data: Optional[Dict] = None, files: Optional[Dict] = None,
                params: Optional[Dict] = None, expected_status: Optional[int] = None,
                headers: Optional[Dict] = None) -> Optional[Any]:
    """Make an API request and return the response data if successful"""
    url = api_url(endpoint)
    debug_info(f"Making {method} request to {url}")
    
    if data:
        debug_info(f"Request data: {json.dumps(data, indent=2)}")
    
    # Determine expected status code if not explicitly provided
    if expected_status is None:
        if method.upper() == "POST" and not files:
            expected_status = 201  # Created for POST requests that create resources
        elif method.upper() == "DELETE" or method.upper() == "PATCH" or method.upper() == "PUT":
            expected_status = 204  # No Content for successful DELETE/PATCH/PUT operations
        else:
            expected_status = 200  # OK for GET and other requests
    
    try:
        # Prepare default headers
        default_headers = {"Accept": "application/json"}
        if headers:
            default_headers.update(headers)
        
        if method.upper() == "GET":
            response = session.get(url, params=params, headers=default_headers)
        elif method.upper() == "POST":
            if files:
                # Don't include Content-Type header for multipart/form-data
                response = session.post(url, data=data, files=files)
            else:
                post_headers = default_headers.copy()
                if "Content-Type" not in post_headers:
                    post_headers["Content-Type"] = "application/json"
                if "Prefer" not in post_headers:
                    post_headers["Prefer"] = "return=representation"
                response = session.post(url, json=data, headers=post_headers)
        elif method.upper() == "PATCH":
            patch_headers = default_headers.copy()
            if "Content-Type" not in patch_headers:
                patch_headers["Content-Type"] = "application/json"
            response = session.patch(url, json=data, headers=patch_headers)
        elif method.upper() == "PUT":
            put_headers = default_headers.copy()
            if "Content-Type" not in put_headers:
                put_headers["Content-Type"] = "application/json"
            response = session.put(url, json=data, headers=put_headers)
        elif method.upper() == "DELETE":
            delete_headers = default_headers.copy()
            if "Content-Type" not in delete_headers:
                delete_headers["Content-Type"] = "application/json"
            response = session.delete(url, headers=delete_headers)
        else:
            log_error(f"Unsupported HTTP method: {method}")
            return None
        
        debug_info(f"Response status code: {response.status_code}")
        
        # Determine expected status code if not explicitly provided
        if expected_status is None:
            if method.upper() == "POST" and not files:
                expected_status = 201  # Created for POST requests that create resources
            elif method.upper() == "PATCH" or method.upper() == "PUT":
                expected_status = 204  # No Content for successful PATCH/PUT operations
            elif method.upper() == "DELETE":
                expected_status = [200, 204]  # DELETE can return 200 (with body) or 204 (no content)
            else:
                expected_status = 200  # OK for GET and other requests
        
        # Special handling for 409 Conflict when creating resources that already exist
        if response.status_code == 409 and method.upper() == "POST" and expected_status == 201:
            debug_info(f"Resource already exists (409 Conflict): {response.text}")
            # Return None but don't treat as an error - caller should handle this
            return None
        
        # Special handling for SQL syntax errors (42601) which might indicate a schema issue
        if response.status_code == 400:
            try:
                error_data = response.json()
                if error_data.get("code") == "42601":  # SQL syntax error
                    debug_info(f"SQL syntax error detected: {error_data.get('message')}")
                    # Log more details about the request for debugging
                    debug_info(f"This might indicate a schema mismatch or invalid column reference")
                    debug_info(f"Request endpoint: {endpoint}")
                    debug_info(f"Request data: {json.dumps(data, indent=2) if data else 'None'}")
            except (json.JSONDecodeError, KeyError):
                pass
            
        # Check if response status is acceptable
        status_ok = False
        if isinstance(expected_status, list):
            status_ok = response.status_code in expected_status
        else:
            # Special case for DELETE requests - accept both 200 and 204
            if method.upper() == "DELETE" and expected_status == 204 and response.status_code == 200:
                status_ok = True
            # Also handle the case when a list of expected statuses is provided
            elif isinstance(expected_status, int) and response.status_code == expected_status:
                status_ok = True
            else:
                status_ok = False
            
        if not status_ok:
            def print_response_debug_info():
                print(f"Response body: {response.text}")
                print(f"API endpoint: {url}")
                print(f"HTTP method: {method}")
                expected_str = expected_status if isinstance(expected_status, int) else f"one of {expected_status}"
                print(f"Expected status: {expected_str}, received: {response.status_code}")
                if data:
                    print(f"Request data: {json.dumps(data, indent=2)}")
                if params:
                    print(f"Query parameters: {params}")
                print(f"Server URL: {API_BASE_URL}")
                print(f"Session cookies: {dict(session.cookies)}")
            
            expected_str = expected_status if isinstance(expected_status, int) else f"one of {expected_status}"
            log_error(f"API request failed. Expected status {expected_str}, got {response.status_code} for {endpoint}", 
                     print_response_debug_info)
            return None
        
        # For 204 No Content responses, return empty dict
        if response.status_code == 204:
            return {}
        
        # For 200 responses to DELETE requests, try to parse as JSON or return empty dict
        if method.upper() == "DELETE" and response.status_code == 200:
            try:
                return response.json()
            except json.JSONDecodeError:
                return {}
        
        try:
            # Try to parse as JSON
            json_response = response.json()
            debug_info(f"Response JSON: {json.dumps(json_response, indent=2)}")
            return json_response
        except json.JSONDecodeError:
            # Some endpoints might not return JSON
            debug_info(f"Response text (not JSON): {response.text}")
            return response.text
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
        return None


def setup_import_definitions(session: requests.Session) -> bool:
    """Create the BRREG import definitions, as test 303 does, from the shipped sample SQL.

    A definition links import steps (import.link_steps_to_definition) and generates its data columns in
    lifecycle callbacks; neither is exposed through the REST API, so the definitions are created by running
    samples/norway/brreg/create-import-definition-*-2024.sql through ./sb psql on the database the API serves.
    """
    log_info("Setting up import definitions...")
    slugs = "brreg_hovedenhet_2024,brreg_underenhet_2024"
    definitions = api_request(session, "GET", f"/rest/import_definition?slug=in.({slugs})")
    if definitions and len(definitions) == 2 and all(d.get("valid") for d in definitions):
        log_success("Import definitions already exist and are valid")
        return True

    data_sources = api_request(session, "GET", "/rest/data_source?code=eq.brreg")
    if not data_sources:
        result = api_request(session, "POST", "/rest/data_source",
                             data={"code": "brreg", "name": "Brønnøysundregistrene", "enabled": True, "custom": True})
        if result is None:
            log_error("Failed to create the BRREG data source")
            return False
        log_success("Created BRREG data source")

    dbname = ISOLATED_DB or os.environ.get("POSTGRES_APP_DB")
    for name in ("hovedenhet", "underenhet"):
        path = WORKSPACE / "samples" / "norway" / "brreg" / f"create-import-definition-{name}-2024.sql"
        try:
            with open(path) as f:
                sb_psql(f.read(), dbname)
        except RuntimeError as e:
            log_error(f"Creating the {name} definition from {path.name} failed: {e}")
            return False

    definitions = api_request(session, "GET", f"/rest/import_definition?slug=in.({slugs})")
    if definitions and len(definitions) == 2 and all(d.get("valid") for d in definitions):
        log_success("Import definitions created and validated successfully")
        return True
    log_error(f"Import definitions not valid after creation: {definitions}")
    return False

def create_import_jobs(session: requests.Session) -> bool:
    """Create import jobs for Norway data"""
    log_info("Creating import jobs...")
    
    # Check if import jobs already exist
    jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
    
    if jobs and len(jobs) >= 8:  # We expect 8 jobs (4 years x 2 types)
        log_success(f"Import jobs already exist ({len(jobs)} found)")
        return True
        
    # Create a dictionary of existing jobs by slug for quick lookup
    existing_jobs = {}
    if jobs:
        for job in jobs:
            existing_jobs[job['slug']] = job
            log_info(f"Found existing job: {job['slug']} (state: {job['state']})")
    
    # Get import definition IDs
    definitions = api_request(session, "GET", "/rest/import_definition?slug=in.(brreg_hovedenhet_2024,brreg_underenhet_2024)")
    
    if not definitions or len(definitions) != 2:
        log_error("Import definitions not found")
        return False
    
    # Check if definitions are valid
    invalid_definitions = [d for d in definitions if not d.get("valid")]
    if invalid_definitions:
        log_error(f"Found {len(invalid_definitions)} invalid import definitions. Please run setup_import_definitions first.")
        for d in invalid_definitions:
            log_info(f"Invalid definition: {d.get('slug')}")
        return False
    
    # Find the definition IDs
    hovedenhet_def_id = None
    underenhet_def_id = None
    
    for definition in definitions:
        if definition.get("slug") == "brreg_hovedenhet_2024":
            hovedenhet_def_id = definition.get("id")
        elif definition.get("slug") == "brreg_underenhet_2024":
            underenhet_def_id = definition.get("id")
    
    if not hovedenhet_def_id or not underenhet_def_id:
        log_error("Could not find import definition IDs")
        return False
    
    # Create import jobs for hovedenhet (legal units)
    years = ["2015", "2016", "2017", "2018"]
    job_slugs = []
    
    # First create all hovedenhet (legal unit) jobs
    for year in years:
        job_slug = f"import_lu_{year}_sht"
        
        # Check if job already exists
        if job_slug in existing_jobs:
            log_success(f"Hovedenhet import job for {year} already exists (state: {existing_jobs[job_slug]['state']})")
            job_slugs.append(job_slug)
            continue
            
        # Create hovedenhet job
        hovedenhet_job = {
            "definition_id": hovedenhet_def_id,
            "slug": job_slug,
            "default_valid_from": f"{year}-01-01",
            "default_valid_to": "infinity",
            "description": f"Import Job for BRREG Hovedenhet {year} Small History Test",
            "note": f"This job handles the import of BRREG Hovedenhet small history test data for {year}."
        }
        
        try:
            result = api_request(session, "POST", "/rest/import_job", data=hovedenhet_job, expected_status=201)
            
            if result is not None:
                log_success(f"Created hovedenhet import job for {year}")
                job_slugs.append(job_slug)
                debug_info(f"Job creation response: {json.dumps(result, indent=2) if isinstance(result, (dict, list)) else result}")
            else:
                # Check if the job was created despite the error (e.g., 409 conflict)
                check_job = api_request(session, "GET", f"/rest/import_job?slug=eq.{job_slug}")
                if check_job and len(check_job) > 0:
                    log_success(f"Hovedenhet import job for {year} already exists (state: {check_job[0]['state']})")
                    job_slugs.append(job_slug)
                else:
                    log_error(f"Failed to create hovedenhet import job for {year}")
                    return False
        except Exception as e:
            # Check if the job was created despite the exception
            check_job = api_request(session, "GET", f"/rest/import_job?slug=eq.{job_slug}")
            if check_job and len(check_job) > 0:
                log_success(f"Hovedenhet import job for {year} already exists (state: {check_job[0]['state']})")
                job_slugs.append(job_slug)
            else:
                log_error(f"Exception creating hovedenhet import job for {year}: {e}")
                return False
    
    # Now create all underenhet (establishment) jobs
    for year in years:
        job_slug = f"import_es_{year}_sht"
        
        # Check if job already exists
        if job_slug in existing_jobs:
            log_success(f"Underenhet import job for {year} already exists (state: {existing_jobs[job_slug]['state']})")
            job_slugs.append(job_slug)
            continue
            
        # Create underenhet job
        underenhet_job = {
            "definition_id": underenhet_def_id,
            "slug": job_slug,
            "default_valid_from": f"{year}-01-01",
            "default_valid_to": "infinity",
            "description": f"Import Job for BRREG Underenhet {year} Small History Test",
            "note": f"This job handles the import of BRREG Underenhet small history test data for {year}."
        }
        
        try:
            result = api_request(session, "POST", "/rest/import_job", data=underenhet_job, expected_status=201)
            
            if result is not None:
                log_success(f"Created underenhet import job for {year}")
                job_slugs.append(job_slug)
                debug_info(f"Job creation response: {json.dumps(result, indent=2) if isinstance(result, (dict, list)) else result}")
            else:
                # Check if the job was created despite the error (e.g., 409 conflict)
                check_job = api_request(session, "GET", f"/rest/import_job?slug=eq.{job_slug}")
                if check_job and len(check_job) > 0:
                    log_success(f"Underenhet import job for {year} already exists (state: {check_job[0]['state']})")
                    job_slugs.append(job_slug)
                else:
                    log_error(f"Failed to create underenhet import job for {year}")
                    return False
        except Exception as e:
            # Check if the job was created despite the exception
            check_job = api_request(session, "GET", f"/rest/import_job?slug=eq.{job_slug}")
            if check_job and len(check_job) > 0:
                log_success(f"Underenhet import job for {year} already exists (state: {check_job[0]['state']})")
                job_slugs.append(job_slug)
            else:
                log_error(f"Exception creating underenhet import job for {year}: {e}")
                return False
    
    # Verify all jobs were created
    jobs = api_request(session, "GET", f"/rest/import_job?slug=in.({','.join(job_slugs)})")
    
    if jobs and len(jobs) == 8:
        log_success("All import jobs created successfully")
        return True
    else:
        log_error(f"Not all import jobs were created. Expected 8, found {len(jobs) if jobs else 0}")
        return False

def upload_data_files(session: requests.Session) -> bool:
    """Upload data files for import jobs"""
    log_info("Uploading data files...")
    
    # Get all import jobs to check their states
    jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
    
    if not jobs:
        log_error("No import jobs found")
        return False
    
    # Create a dictionary of jobs by slug for quick lookup
    job_dict = {job['slug']: job for job in jobs}
    
    # Define file paths and corresponding job slugs
    file_mappings = [
        ("samples/norway/small-history/2015-enheter.csv", "import_lu_2015_sht"),
        ("samples/norway/small-history/2016-enheter.csv", "import_lu_2016_sht"),
        ("samples/norway/small-history/2017-enheter.csv", "import_lu_2017_sht"),
        ("samples/norway/small-history/2018-enheter.csv", "import_lu_2018_sht"),
        ("samples/norway/small-history/2015-underenheter.csv", "import_es_2015_sht"),
        ("samples/norway/small-history/2016-underenheter.csv", "import_es_2016_sht"),
        ("samples/norway/small-history/2017-underenheter.csv", "import_es_2017_sht"),
        ("samples/norway/small-history/2018-underenheter.csv", "import_es_2018_sht")
    ]
    
    for file_path, job_slug in file_mappings:
        # Check if job exists and its state
        if job_slug in job_dict:
            job_state = job_dict[job_slug]['state']
            # Skip upload if job is already in progress or completed
            if job_state not in ['created', 'waiting_for_upload', 'failed']:
                log_info(f"Skipping upload for job {job_slug} (state: {job_state})")
                continue
        full_path = WORKSPACE / file_path
        
        if not full_path.exists():
            log_error(f"Data file not found: {file_path}")
            return False
        
        log_info(f"Uploading {file_path} for job {job_slug}...")
        
        # Read the CSV file content
        with open(full_path, 'r') as f:
            csv_content = f.read()
            
            # Get the job details to determine the upload table name
            job_details = api_request(session, "GET", f"/rest/import_job?slug=eq.{job_slug}")
            
            if not job_details or len(job_details) == 0:
                log_error(f"Could not get details for job {job_slug}")
                return False
                
            # Get the upload table name directly from the job
            upload_table_name = job_details[0].get("upload_table_name")
            if not upload_table_name:
                log_error(f"Could not determine upload table name for job {job_slug}")
                return False
                
            log_info(f"Using upload table '{upload_table_name}' for job {job_slug}")
            
            # Add job slug as a header to associate the upload with the job
            headers = {
                "Content-Type": "text/csv",
                "X-Import-Job-Slug": job_slug
            }
            
            # Construct the URL for the upload
            upload_url = api_url(f"/rest/{upload_table_name}")
            log_info(f"Posting to URL: {upload_url}")
            
            # Debug the request
            debug_info(f"Request headers: {headers}")
            debug_info(f"Session cookies: {dict(session.cookies)}")
            debug_info(f"Session headers: {dict(session.headers)}")
            
            # Post to the REST endpoint for the upload table
            response = session.post(
                upload_url,
                headers=headers,
                data=csv_content
            )
            
            if response.status_code in [200, 201]:
                log_success(f"Uploaded {file_path} successfully to upload table {upload_table_name}")
                
                # Verify the job state changed after upload
                time.sleep(1)  # Give the server a moment to process
                updated_job = api_request(session, "GET", f"/rest/import_job?slug=eq.{job_slug}")
                
                if updated_job and len(updated_job) > 0:
                    new_state = updated_job[0]['state']
                    log_info(f"Job {job_slug} state after upload: {new_state}")
                    
                    if new_state == 'waiting_for_upload':
                        log_warning(f"Job {job_slug} still in waiting_for_upload state after upload - check that worker is running with `docker compose ps worker` and `docker compose logs -f --since 5m worker` and debug with `VERBOSE=1 DEBUG=true docker compose up worker --build`")
            else:
                def print_upload_error():
                    print(f"{RED}Response status: {response.status_code}{NC}")
                    print(f"{RED}Response body: {response.text}{NC}")
                    print(f"{RED}Request URL: {upload_url}{NC}")
                    print(f"{RED}Request headers: {headers}{NC}")
                    print(f"{RED}Session cookies: {dict(session.cookies)}{NC}")
                
                log_error(f"Failed to upload {file_path}", print_upload_error)
                return False
    
    # Final check to ensure all jobs have moved past waiting_for_upload state
    time.sleep(2)  # Give the server a moment to process
    jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
    
    if jobs:
        waiting_jobs = [job for job in jobs if job['state'] == 'waiting_for_upload']
        if waiting_jobs:
            log_warning(f"{len(waiting_jobs)} jobs still in waiting_for_upload state")
                
    return True

import threading
from queue import Queue, Empty

def wait_for_worker_processing_of_import_jobs(session: requests.Session) -> bool:
    """Wait for import jobs to be processed by the worker"""
    log_info("Processing import jobs...")
    
    # Get all import jobs
    jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
    
    if not jobs:
        log_error("No import jobs found")
        return False
    
    # Check initial state
    for job in jobs:
        log_info(f"Job {job['slug']} initial state: {job['state']}")
        
    # Create a shared queue for SSE events and a flag for completion
    event_queue = Queue()
    stop_event = threading.Event()
    
    # Track job status
    job_status = {job['id']: job['state'] for job in jobs}
    
    # Check if all jobs are already completed before starting SSE
    if all(state in ['finished', 'rejected'] for state in job_status.values()):
        log_success("All jobs are already completed, no need to monitor")
        return True
    
    # Function to check if all jobs are completed (including deleted)
    def check_all_completed():
        completed_count = sum(1 for state in job_status.values() if state in ['finished', 'rejected', 'deleted'])
        log_info(f"Job completion status: {completed_count}/{len(jobs)} jobs completed, rejected, or deleted")
        return completed_count == len(jobs)

    # Get job IDs for monitoring
    job_ids = [job['id'] for job in jobs]
    job_id_str = ",".join(str(job_id) for job_id in job_ids)
    
    # Thread function to monitor SSE events
    def sse_monitor_thread():
        try:
            # Clone the session cookies and headers for the SSE connection
            sse_session = requests.Session()
            sse_session.cookies.update(session.cookies)
            
            # Prepare the SSE request
            sse_url = f"{API_BASE_URL}/api/sse/import-jobs?ids={job_id_str}"
            log_info(f"SSE thread connecting to endpoint: {sse_url}")
            
            # Start the SSE request
            sse_response = sse_session.get(
                sse_url,
                stream=True,
                headers={"Accept": "text/event-stream"}
            )
            
            if sse_response.status_code != 200:
                event_queue.put(("error", f"SSE connection failed with status {sse_response.status_code}"))
                event_queue.put(("error_details", {
                    "status": sse_response.status_code,
                    "body": sse_response.text,
                    "headers": dict(sse_response.headers),
                    "url": sse_url
                }))
                return
            
            event_queue.put(("info", "SSE connection established (HTTP 200 OK)"))

            # Process SSE events line by line
            buffer = ""
            event_type = None
            for line_bytes in sse_response.iter_lines():
                if stop_event.is_set():
                    log_info("SSE thread: Stop event received, breaking loop.")
                    break

                line = line_bytes.decode('utf-8')
                event_queue.put(("raw_line", line)) # Log raw lines for debugging

                if not line: # Empty line signifies end of an event
                    if buffer and event_type:
                        event_queue.put(("debug", f"Processing event: type={event_type}, data={buffer}"))
                        if event_type == "message": # Default event type if none specified
                            try:
                                data = json.loads(buffer)
                                event_queue.put(("data", data))
                            except json.JSONDecodeError:
                                event_queue.put(("warning", f"Failed to parse SSE data: {buffer}"))
                        elif event_type == "heartbeat":
                            try:
                                data = json.loads(buffer)
                                event_queue.put(("heartbeat", data))
                            except json.JSONDecodeError:
                                event_queue.put(("warning", f"Failed to parse heartbeat data: {buffer}"))
                        else:
                             event_queue.put(("warning", f"Received unknown event type: {event_type}"))
                    # Reset for next event
                    buffer = ""
                    event_type = None
                    continue

                if line.startswith("event:"):
                    event_type = line[6:].strip()
                elif line.startswith("data:"):
                    buffer += line[5:].strip() # Append data, removing "data:" prefix
                elif line.startswith("retry:"):
                    event_queue.put(("info", f"Received retry directive: {line}"))
                elif line.startswith(":"): # Comment line, often used for heartbeats without data
                    event_queue.put(("debug", f"Received comment line: {line}"))
                    # Treat simple comments as potential heartbeats if no event type is set
                    if not event_type:
                         event_type = "heartbeat" # Assume simple comment is heartbeat
                         buffer = "{}" # Provide empty JSON object for heartbeat handler
                else:
                    event_queue.put(("warning", f"Received unexpected SSE line: {line}"))

            log_info("SSE thread: iter_lines loop finished.")
            # Close the SSE connection if not already closed
            if sse_response:
                sse_response.close()
            event_queue.put(("info", "SSE connection closed"))
            
        except Exception as e:
            event_queue.put(("error", f"Error in SSE thread: {str(e)}"))
    
    # Start the SSE monitor thread
    sse_thread = threading.Thread(target=sse_monitor_thread)
    sse_thread.daemon = True
    sse_thread.start()
    
    # Process events from the queue
    all_completed = False
    timeout = time.time() + 300  # 5 minutes timeout
    last_heartbeat = time.time()
    heartbeat_count = 0
    
    try:
        # Wait for initial connection
        initial_timeout = time.time() + 10  # 10 seconds for initial connection
        connection_established = False
        
        while time.time() < initial_timeout and not connection_established:
            try:
                event_type, event_data = event_queue.get(timeout=1)
                
                if event_type == "error":
                    log_error(event_data)
                    if event_queue.qsize() > 0:
                        error_type, error_details = event_queue.get(timeout=1)
                        if error_type == "error_details":
                            def print_sse_error_details():
                                print(f"{RED}SSE response status: {error_details['status']}{NC}")
                                print(f"{RED}SSE response body: {error_details['body']}{NC}")
                                print(f"{RED}SSE response headers: {error_details['headers']}{NC}")
                                print(f"{RED}SSE request URL: {error_details['url']}{NC}")
                            
                            log_error("SSE connection failed", print_sse_error_details)
                    stop_event.set()
                    return False
                
                if event_type == "info" and event_data == "SSE connection established":
                    log_success("SSE connection established")
                    connection_established = True
                
                event_queue.task_done()
            except Empty:
                pass
        
        if not connection_established:
            log_error("Timed out waiting for SSE connection to establish")
            stop_event.set()
            return False
        
        # Main event processing loop
        while time.time() < timeout and not all_completed:
            # Check if jobs have been updated directly
            if time.time() % 10 < 1:  # Check roughly every 10 seconds
                updated_jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
                if updated_jobs:
                    for job in updated_jobs:
                        job_id = job['id']
                        new_state = job['state']
                        old_state = job_status.get(job_id)
                        
                        if old_state != new_state:
                            log_info(f"Job {job['slug']} state changed (poll): {old_state} -> {new_state}")
                            job_status[job_id] = new_state
                    
                    # Check if all jobs are completed after polling
                    if check_all_completed():
                        log_success("All jobs completed (detected by polling)")
                        all_completed = True
                        break
            
            # Check if we've been idle too long (no heartbeats)
            if time.time() - last_heartbeat > 15:  # 15 seconds without heartbeat
                log_info("No recent heartbeats, checking job status directly")
                updated_jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
                if updated_jobs:
                    for job in updated_jobs:
                        job_id = job['id']
                        new_state = job['state']
                        old_state = job_status.get(job_id)
                        
                        if old_state != new_state:
                            log_info(f"Job {job['slug']} state changed (poll): {old_state} -> {new_state}")
                            job_status[job_id] = new_state
                    
                    # Check if all jobs are completed after polling
                    if check_all_completed():
                        log_success("All jobs completed (detected by polling during idle period)")
                        all_completed = True
                        break
                
                # Reset heartbeat timer
                last_heartbeat = time.time()
            
            # Process events from the queue
            try:
                event_type, event_data = event_queue.get(timeout=1)
                
                if event_type == "error":
                    log_warning(f"SSE error: {event_data}")
                
                elif event_type == "data":
                    # Handle connection established message
                    if isinstance(event_data, dict) and event_data.get('type') == 'connection_established':
                        log_info(f"SSE connection established for job IDs: {event_data.get('jobIds', [])}")
                    
                    # Handle structured job updates { verb: '...', import_job: { ... } }
                    elif isinstance(event_data, dict) and 'verb' in event_data and 'import_job' in event_data:
                        verb = event_data['verb']
                        job_data = event_data['import_job'] # Use 'import_job' key

                        if verb == 'DELETE':
                            job_id = job_data.get('id')
                            if job_id in job_status:
                                log_info(f"Job {job_id} deleted (SSE)")
                                job_status[job_id] = 'deleted' # Mark as deleted
                        elif verb in ['INSERT', 'UPDATE']:
                            job_id = job_data.get('id')
                            new_state = job_data.get('state')
                            old_state = job_status.get(job_id)

                            if job_id in job_status and old_state != new_state:
                                log_info(f"Job {job_data.get('slug', job_id)} state changed (SSE): {old_state} -> {new_state} (verb: {verb})")
                                job_status[job_id] = new_state

                                # Log additional details if available
                                if 'message' in job_data:
                                    log_info(f"Job message: {job_data['message']}")
                                if 'import_completed_pct' in job_data:
                                    log_info(f"Job progress: {job_data['import_completed_pct']}%")
                        else:
                            log_warning(f"Received unknown verb in job update: {verb}")

                        # Check if all jobs are completed after each state change
                        # Include 'deleted' as a completed state for this check
                        if check_all_completed():
                            log_success("All jobs completed or deleted (detected by SSE)")
                            all_completed = True
                            break
                    else:
                        # Log unexpected data format
                        log_warning(f"Received unexpected data format: {event_data}")

                elif event_type == "heartbeat":
                    heartbeat_count += 1
                    last_heartbeat = time.time()
                    # Log first few and then periodically
                    if heartbeat_count <= 5 or heartbeat_count % 10 == 0:
                        log_info(f"Received SSE heartbeat ({heartbeat_count}): {event_data}")

                elif event_type == "raw_line":
                    # Log raw lines only if DEBUG is enabled
                    debug_info(f"SSE Raw: {event_data}")

                elif event_type == "debug":
                    debug_info(f"SSE Debug: {event_data}")

                elif event_type == "warning":
                    log_warning(f"SSE Warning: {event_data}")

                elif event_type == "info":
                    log_info(f"SSE Info: {event_data}")

                event_queue.task_done()

            except Empty:
                # No events in the queue, check if we need to trigger processing
                if not any(state in ['processing', 'validating'] for state in job_status.values()):
                    waiting_jobs = [job_id for job_id, state in job_status.items() if state == 'waiting_for_upload']
                    if waiting_jobs:
                        log_info(f"Found {len(waiting_jobs)} jobs still waiting for upload, triggering processing")
                        # The worker must do this, so output approriate instructions to check/debug found elsewhere.
        
        # Stop the SSE thread
        stop_event.set()
        
        # Final check of job status
        log_info("Performing final job status check...")
        updated_jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
        if updated_jobs:
            # Print detailed status of each job
            for job in updated_jobs:
                job_id = job['id']
                new_state = job['state']
                old_state = job_status.get(job_id)
                job_status[job_id] = new_state
                
                if old_state != new_state:
                    log_info(f"Job {job['slug']} final state update: {old_state} -> {new_state}")
                else:
                    log_info(f"Job {job['slug']} final state: {new_state}")
            
            all_completed = check_all_completed()
            
            # If all jobs are in a terminal state (finished or rejected), consider the process complete
            if all(state in ['finished', 'rejected'] for state in job_status.values()):
                log_success("All jobs are in terminal states (finished or rejected)")
                all_completed = True
        
        # Wait for the thread to finish
        sse_thread.join(timeout=5)
        
    except Exception as e:
        log_error(f"Error during job monitoring: {e}")
        stop_event.set()
        return False
    
    if not all_completed:
        log_warning("Not all jobs completed within the timeout period")
        
        # Show current status
        updated_jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
        if updated_jobs:
            for job in updated_jobs:
                log_info(f"Job {job['slug']} final state: {job['state']}")
        
        return False
    
    # Check for any rejected jobs
    rejected_jobs = [job_id for job_id, state in job_status.items() if state == 'rejected']
    if rejected_jobs:
        log_warning(f"{len(rejected_jobs)} jobs rejected")
        
        # Get details of rejected jobs
        updated_jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
        if updated_jobs:
            for job in updated_jobs:
                if job['state'] == 'rejected':
                    log_warning(f"Job {job['slug']} rejected")
        
        return False
    
    log_success("All import jobs completed successfully")
    return True

def wait_for_worker_derive(session: requests.Session) -> bool:
    """Wait for worker to finish deriving statistical units and reports
    
    Connects to /api/sse/worker_status SSE endpoint and monitors the worker status
    until both is_deriving_statistical_units and is_deriving_reports are false.
    """
    log_info("Waiting for worker to finish deriving statistical units and reports...")
    
    # Create a shared queue for SSE events and a flag for completion
    event_queue = Queue()
    stop_event = threading.Event()
    
    # Track derivation status
    derivation_status = {
        "isDerivingUnits": True,  # Assume true initially
        "isDerivingReports": True  # Assume true initially
    }
    
    # Function to check if all derivation is completed
    def check_all_completed():
        return not derivation_status["isDerivingUnits"] and not derivation_status["isDerivingReports"]
    
    # Thread function to monitor SSE events
    def sse_monitor_thread():
        try:
            # Clone the session cookies and headers for the SSE connection
            sse_session = requests.Session()
            sse_session.cookies.update(session.cookies)
            
            # Prepare the SSE request
            sse_url = f"{API_BASE_URL}/api/sse/worker_status"
            log_info(f"SSE thread connecting to endpoint: {sse_url}")
            
            # Start the SSE request
            sse_response = sse_session.get(
                sse_url,
                stream=True,
                headers={"Accept": "text/event-stream"}
            )
            
            if sse_response.status_code != 200:
                event_queue.put(("error", f"SSE connection failed with status {sse_response.status_code}"))
                event_queue.put(("error_details", {
                    "status": sse_response.status_code,
                    "body": sse_response.text,
                    "headers": dict(sse_response.headers),
                    "url": sse_url
                }))
                return
            
            event_queue.put(("info", "SSE connection established"))
            
            # Process SSE events line by line
            for line_bytes in sse_response.iter_lines():
                if stop_event.is_set():
                    break
                
                line = line_bytes.decode('utf-8')

                if line.startswith("data:"):
                    try:
                        data = json.loads(line[5:].strip())
                        event_queue.put(("data", data))
                    except json.JSONDecodeError:
                        event_queue.put(("warning", f"Failed to parse SSE data: {line[5:].strip()}"))
                elif line.startswith("event:"):
                    event_type = line[6:].strip()
                    event_queue.put(("event", {"type": event_type, "data": None}))
                elif line.startswith(":"): # comment/heartbeat
                    event_queue.put(("heartbeat", {}))
            
            # Close the SSE connection
            sse_response.close()
            event_queue.put(("info", "SSE connection closed"))
            
        except Exception as e:
            event_queue.put(("error", f"Error in SSE thread: {str(e)}"))
    
    # Start the SSE monitor thread
    sse_thread = threading.Thread(target=sse_monitor_thread)
    sse_thread.daemon = True
    sse_thread.start()
    
    # Process events from the queue
    all_completed = False
    timeout = time.time() + 300  # 5 minutes timeout
    last_activity = time.time()
    
    try:
        # Wait for initial connection
        initial_timeout = time.time() + 10  # 10 seconds for initial connection
        connection_established = False
        
        while time.time() < initial_timeout and not connection_established:
            try:
                event_type, event_data = event_queue.get(timeout=1)
                
                if event_type == "error":
                    log_error(event_data)
                    if event_queue.qsize() > 0:
                        error_type, error_details = event_queue.get(timeout=1)
                        if error_type == "error_details":
                            def print_sse_error_details():
                                print(f"{RED}SSE response status: {error_details['status']}{NC}")
                                print(f"{RED}SSE response body: {error_details['body']}{NC}")
                                print(f"{RED}SSE response headers: {error_details['headers']}{NC}")
                                print(f"{RED}SSE request URL: {error_details['url']}{NC}")
                            
                            log_error("SSE connection failed", print_sse_error_details)
                    stop_event.set()
                    return False
                
                if event_type == "info" and event_data == "SSE connection established":
                    log_success("SSE connection established")
                    connection_established = True
                
                event_queue.task_done()
            except Empty:
                pass
        
        if not connection_established:
            log_error("Timed out waiting for SSE connection to establish")
            stop_event.set()
            return False
        
        # Check initial status directly
        log_info("Checking initial worker status...")
        try:
            # Make a direct API call to get current status
            status_response = api_request(session, "GET", "/api/diagnostics")
            if status_response and "diagnostics" in status_response:
                worker_status = status_response["diagnostics"].get("workerStatus", {})
                derivation_status["isDerivingUnits"] = worker_status.get("isDerivingUnits", False)
                derivation_status["isDerivingReports"] = worker_status.get("isDerivingReports", False)
                
                log_info(f"Initial status - Deriving units: {derivation_status['isDerivingUnits']}, " +
                         f"Deriving reports: {derivation_status['isDerivingReports']}")
                
                # If already completed, we can exit early
                if check_all_completed():
                    log_success("Worker is not currently deriving any data")
                    all_completed = True
                    stop_event.set()
                    return True
        except Exception as e:
            log_warning(f"Failed to get initial worker status: {e}")
        
        # Main event processing loop
        while time.time() < timeout and not all_completed:
            # Check if we've been idle too long
            if time.time() - last_activity > 30:  # 30 seconds without activity
                log_info("No recent events, checking worker status directly")
                try:
                    # Make a direct API call to get current status
                    status_response = api_request(session, "GET", "/api/diagnostics")
                    if status_response and "diagnostics" in status_response:
                        worker_status = status_response["diagnostics"].get("workerStatus", {})
                        derivation_status["isDerivingUnits"] = worker_status.get("isDerivingUnits", False)
                        derivation_status["isDerivingReports"] = worker_status.get("isDerivingReports", False)
                        
                        log_info(f"Current status - Deriving units: {derivation_status['isDerivingUnits']}, " +
                                 f"Deriving reports: {derivation_status['isDerivingReports']}")
                        
                        # Check if all derivation is completed
                        if check_all_completed():
                            log_success("Worker has finished all derivation tasks (detected by polling)")
                            all_completed = True
                            break
                except Exception as e:
                    log_warning(f"Failed to get worker status: {e}")
                
                # Reset activity timer
                last_activity = time.time()
            
            # Process events from the queue
            try:
                event_type, event_data = event_queue.get(timeout=1)
                last_activity = time.time()
                
                if event_type == "error":
                    log_warning(f"SSE error: {event_data}")
                
                elif event_type == "data":
                    payload = event_data
                    status_type = payload.get("type")
                    status_value = payload.get("status")

                    if status_type == "is_deriving_statistical_units":
                        key = "isDerivingUnits"
                        old_status = derivation_status[key]
                        derivation_status[key] = status_value
                        if old_status != status_value:
                             log_info(f"Deriving units status changed: {old_status} -> {status_value}")
                    elif status_type == "is_deriving_reports":
                        key = "isDerivingReports"
                        old_status = derivation_status[key]
                        derivation_status[key] = status_value
                        if old_status != status_value:
                             log_info(f"Deriving reports status changed: {old_status} -> {status_value}")

                    # Check if all derivation is completed
                    if check_all_completed():
                        log_success("Worker has finished all derivation tasks (detected by SSE)")
                        all_completed = True
                        break
                
                elif event_type == "event" and event_data["type"] == "connected":
                    log_info("Received connected event from SSE")
                
                event_queue.task_done()
            
            except Empty:
                # No events in the queue, continue waiting
                pass
        
        # Stop the SSE thread
        stop_event.set()
        
        # Final check of derivation status
        log_info("Performing final derivation status check...")
        try:
            # Make a direct API call to get current status
            status_response = api_request(session, "GET", "/api/diagnostics")
            if status_response and "diagnostics" in status_response:
                worker_status = status_response["diagnostics"].get("workerStatus", {})
                derivation_status["isDerivingUnits"] = worker_status.get("isDerivingUnits", False)
                derivation_status["isDerivingReports"] = worker_status.get("isDerivingReports", False)
                
                log_info(f"Final status - Deriving units: {derivation_status['isDerivingUnits']}, " +
                         f"Deriving reports: {derivation_status['isDerivingReports']}")
                
                all_completed = check_all_completed()
            else:
                log_warning("Failed to get final worker status")
        except Exception as e:
            log_warning(f"Error during final status check: {e}")
        
        # Wait for the thread to finish
        sse_thread.join(timeout=5)
        
    except Exception as e:
        log_error(f"Error during worker derivation monitoring: {e}")
        stop_event.set()
        return False
    
    if not all_completed:
        log_warning("Worker derivation did not complete within the timeout period")
        return False
    
    log_success("Worker has finished deriving all statistical units and reports")
    return True


def verify_imported_data(session: requests.Session) -> bool:
    """Verify that data was imported correctly"""
    log_info("Verifying imported data...")
    
    # Check statistical units
    units = api_request(session, "GET", "/rest/statistical_unit?limit=100")
    
    if not units:
        log_error("No statistical units found")
        return False
    
    log_success(f"Found {len(units)} statistical units")
    
    # Check for different unit types
    legal_units = [u for u in units if u.get('unit_type') == 'legal_unit']
    establishments = [u for u in units if u.get('unit_type') == 'establishment']
    
    log_info(f"Found {len(legal_units)} legal units")
    log_info(f"Found {len(establishments)} establishments")
    
    if not legal_units or not establishments:
        log_warning("Missing expected unit types in the imported data")
        return False
    
    # Check for time segments
    time_segments = api_request(session, "GET", "/rest/timesegments_def?limit=100")
    
    if not time_segments:
        log_warning("No time segments found")
        return False
    
    log_success(f"Found {len(time_segments)} time segments")
    
    # Check for timelines
    legal_unit_timelines = api_request(session, "GET", "/rest/timeline_legal_unit_def?limit=100")
    establishment_timelines = api_request(session, "GET", "/rest/timeline_establishment_def?limit=100")
    
    if not legal_unit_timelines or not establishment_timelines:
        log_warning("Missing expected timelines")
        return False
    
    log_success(f"Found {len(legal_unit_timelines)} legal unit timelines")
    log_success(f"Found {len(establishment_timelines)} establishment timelines")
    
    return True

def delete_imported_data(session: requests.Session) -> bool:
    """Delete all imported data and definitions"""
    log_info("Deleting imported data...")
    
    # Step 1: Delete import jobs
    log_info("Deleting import jobs...")
    jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht")
    
    if jobs:
        for job in jobs:
            job_id = job['id']
            job_slug = job['slug']
            
            # Delete the job
            result = api_request(session, "DELETE", f"/rest/import_job?id=eq.{job_id}", expected_status=204)
            if result is not None:
                log_success(f"Deleted import job: {job_slug}")
            else:
                log_warning(f"Failed to delete import job: {job_slug}")
    else:
        log_info("No import jobs found to delete")
    
    # Step 2: Delete import definitions
    log_info("Deleting import definitions...")
    definitions = api_request(session, "GET", "/rest/import_definition?slug=in.(brreg_hovedenhet_2024,brreg_underenhet_2024)")
    
    if definitions:
        for definition in definitions:
            def_id = definition['id']
            def_slug = definition['slug']
            
            # First set to draft mode to allow deletion
            update_result = api_request(session, "PATCH", f"/rest/import_definition?id=eq.{def_id}", 
                                       data={"draft": True, "valid": False}, expected_status=204)
            
            if update_result is not None:
                # Delete all mappings for this definition using batch delete
                result = api_request(
                    session, 
                    "DELETE", 
                    f"/rest/import_mapping?definition_id=eq.{def_id}",
                    expected_status=204,
                    headers={"Prefer": "return=representation"}
                )
                if result is not None:
                    log_success(f"Deleted all mappings for definition {def_slug}")
                else:
                    log_warning(f"Failed to delete mappings for definition {def_slug}")
                
                # Delete all source columns for this definition using batch delete
                result = api_request(
                    session, 
                    "DELETE", 
                    f"/rest/import_source_column?definition_id=eq.{def_id}",
                    expected_status=204,
                    headers={"Prefer": "return=representation"}
                )
                if result is not None:
                    log_success(f"Deleted all source columns for definition {def_slug}")
                else:
                    log_warning(f"Failed to delete source columns for definition {def_slug}")
                
                # Now delete the definition
                result = api_request(session, "DELETE", f"/rest/import_definition?id=eq.{def_id}", expected_status=204)
                if result is not None:
                    log_success(f"Deleted import definition: {def_slug}")
                else:
                    log_warning(f"Failed to delete import definition: {def_slug}")
            else:
                log_warning(f"Failed to set definition {def_slug} to draft mode for deletion")
    else:
        log_info("No import definitions found to delete")
    
    # Step 3: Delete data source
    log_info("Deleting data source...")
    data_sources = api_request(session, "GET", "/rest/data_source?code=eq.brreg")
    
    if data_sources and len(data_sources) > 0:
        data_source_id = data_sources[0]["id"]
        result = api_request(session, "DELETE", f"/rest/data_source?id=eq.{data_source_id}", expected_status=204)
        if result is not None:
            log_success("Deleted BRREG data source")
        else:
            log_warning("Failed to delete BRREG data source")
    else:
        log_info("No BRREG data source found to delete")
    
    # Step 4: Delete statistical units
    log_info("Deleting statistical units...")
    
    # First delete establishments (must be done before legal units due to foreign key constraints)
    result = api_request(
        session, 
        "DELETE", 
        "/rest/statistical_unit?unit_type=eq.establishment",
        expected_status=204,
        headers={"Prefer": "return=representation"}
    )
    if result is not None:
        if isinstance(result, list):
            log_success(f"Deleted {len(result)} establishments")
            debug_info(f"Deleted establishment IDs: {[unit.get('id') for unit in result]}")
        else:
            log_success("Deleted establishments")
    else:
        log_warning("Failed to delete establishments or none found")
    
    # Then delete legal units
    result = api_request(
        session, 
        "DELETE", 
        "/rest/statistical_unit?unit_type=eq.legal_unit",
        expected_status=204,
        headers={"Prefer": "return=representation"}
    )
    if result is not None:
        if isinstance(result, list):
            log_success(f"Deleted {len(result)} legal units")
            debug_info(f"Deleted legal unit IDs: {[unit.get('id') for unit in result]}")
        else:
            log_success("Deleted legal units")
    else:
        log_warning("Failed to delete legal units or none found")
    
    # Verify deletion
    units = api_request(session, "GET", "/rest/statistical_unit?limit=10")
    if not units or len(units) == 0:
        log_success("All statistical units deleted successfully")
    else:
        log_warning(f"Some statistical units remain after deletion ({len(units)} found)")
    
    return True

def create_test_users() -> bool:
    """Create test users using the setup.sql script"""
    log_info("Creating test users if they don't exist...")
    
    setup_sql_path = WORKSPACE / "test" / "setup.sql"
    manage_script_path = WORKSPACE / "sb"
    
    if not setup_sql_path.exists():
        log_error(f"Setup SQL file not found: {setup_sql_path}")
        return False
        
    if not manage_script_path.exists():
        log_error(f"Manage script not found: {manage_script_path}")
        return False
        
    try:
        # Read the SQL content
        with open(setup_sql_path, 'r') as f:
            sql_content = f.read()
            
        # Execute the manage script with psql command and pass SQL via stdin
        process = subprocess.run(
            [str(manage_script_path), "psql"],
            input=sql_content,
            text=True,
            capture_output=True,
            check=False # Don't raise exception on non-zero exit code
        )
        
        # Log output for debugging
        debug_info(f"psql command stdout:\n{process.stdout}")
        debug_info(f"psql command stderr:\n{process.stderr}")
        
        # Check exit code - psql might return non-zero if users already exist, which is okay
        if process.returncode != 0:
            # Check stderr for common "already exists" errors, ignore them
            if "already exists" in process.stderr.lower():
                log_success("Test users already exist or were created successfully (ignored 'already exists' errors)")
                return True
            else:
                log_warning(f"psql command failed with exit code {process.returncode}")
                log_warning(f"stderr: {process.stderr}")
                # Don't fail the whole script, just warn
                return False
        
        log_success("Test users created successfully")
        return True
        
    except FileNotFoundError:
        log_error(f"Command not found: {manage_script_path}")
        return False
    except Exception as e:
        log_error(f"Error running setup.sql: {e}")
        return False

def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Import or delete Norway small history data')
    parser.add_argument('action', choices=['create', 'delete'], 
                        help='Action to perform: create (import data) or delete (clean up)')
    parser.add_argument('--isolated', action='store_true',
                        help='Use an own database from the test template, an own PostgREST and the worker run to idle')
    parser.add_argument('--cleanup', action='store_true',
                        help='With --isolated: drop the database afterwards (default: retain it for inspection)')
    return parser.parse_args()

def main():
    """Main test sequence. Returns True on success."""
    args = parse_args()
    if not args.isolated:
        return run(args)
    if args.action != "create":
        log_error("--isolated runs create only: its database is new and holds nothing to delete")
        return False
    ok = False
    try:
        isolated_setup()
        ok = run(args)
    finally:
        isolated_teardown(drop_db=args.cleanup)
    return ok


def run(args):
    """The import sequence against API_BASE_URL. Returns True on success."""
    action = args.action
    
    if action == "create":
        print(f"\n{BLUE}=== Starting Norway Small History Import Test via REST API ==={NC}\n")
    else:
        print(f"\n{BLUE}=== Starting Norway Small History Cleanup via REST API ==={NC}\n")
    
    print(f"{BLUE}Using API URL: {API_BASE_URL}{NC}")
    
    # Create a session for API requests
    session = requests.Session()
    
    # Check if the server is reachable
    try:
        response = requests.get(api_url("/rest/rpc/auth_status"), timeout=5)
        log_info(f"Server is reachable. Status: {response.status_code}")
    except requests.RequestException as e:
        log_error(f"Server is not reachable at {API_BASE_URL}: {e}", 
                 lambda: print(f"{RED}Please check if the server is running and the CADDY_HTTP_BIND_ADDRESS environment variable is correct.{NC}"))
        return False
    
    # Login as admin
    admin_id = api_login(session, ADMIN_EMAIL, ADMIN_PASSWORD)
    if not admin_id:
        log_error(f"Admin login failed for {ADMIN_EMAIL}, cannot proceed with tests", 
                 lambda: print(f"{RED}Please verify the admin credentials and server configuration.{NC}"))
        return False
    if args.isolated:
        isolated_authorize(session)
    
    if action == "create":
        # Create test users first (only for 'create' action); --isolated loaded them with the database.
        if not args.isolated and not create_test_users():
            log_warning("Failed to create test users, proceeding anyway...")
            # Don't exit, maybe they already exist
            
        # Run Norway setup if needed
        log_info("Setting up Statbus for Norway...")
        try:
            # Check if Norway setup is already done by checking for activity categories
            categories = api_request(session, "GET", "/rest/activity_category_enabled_custom?limit=1")
            
            if categories and len(categories) > 0:
                log_success("Norway setup already completed")
            else:
                log_info("Performing Norway setup steps...")
                
                # Step 1: Set activity category standard to NACE v2.1
                # First get the activity_category_standard ID for NACE v2.1
                standards = api_request(session, "GET", "/rest/activity_category_standard?code=eq.nace_v2.1")
                if not standards or len(standards) == 0:
                    log_error("NACE v2.1 standard not found")
                    return False
                
                nace_id = standards[0]["id"]
                
                # Settings as samples/norway/settings.sql: NACE v2.1, Norway, the initial region version.
                countries = api_request(session, "GET", "/rest/country?iso_2=eq.NO&select=id")
                region_versions = api_request(session, "GET", "/rest/region_version?code=eq.initial&select=id")
                if not countries or not region_versions:
                    log_error("Country NO or region version 'initial' not found")
                    return False
                settings_update = {
                    "activity_category_standard_id": nace_id,
                    "country_id": countries[0]["id"],
                    "region_version_id": region_versions[0]["id"],
                }
                
                # Check if settings exist
                existing_settings = api_request(session, "GET", "/rest/settings")
                
                if existing_settings and len(existing_settings) > 0:
                    # Update existing settings
                    update_result = api_request(session, "PATCH", "/rest/settings?only_one_setting=eq.true", 
                                               data=settings_update)
                    if update_result is not None:
                        log_success("Updated settings to use NACE v2.1")
                    else:
                        log_warning("Failed to update settings")
                else:
                    # Insert new settings
                    insert_result = api_request(session, "POST", "/rest/settings", data=settings_update)
                    if insert_result is not None:
                        log_success("Inserted settings to use NACE v2.1")
                    else:
                        log_warning("Failed to insert settings")
                
                # Step 2: Import activity categories
                log_info("Importing activity categories...")
                activity_file = WORKSPACE / "samples" / "norway" / "activity_category" / "activity_category_norway.csv"
                
                if not activity_file.exists():
                    log_error(f"Activity category file not found: {activity_file}")
                    return False
                
                with open(activity_file, 'rb') as f:
                    files = {'file': (activity_file.name, f, 'text/csv')}
                    
                    # Use the REST endpoint for direct batch insert of activity categories
                    with open(activity_file, 'r') as f:
                        csv_content = f.read()
                    
                    response = session.post(
                        api_url("/rest/activity_category_enabled_custom"),
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code in (200, 201):
                        log_success("Uploaded activity categories successfully")
                    else:
                        log_warning(f"Failed to upload activity categories: {response.status_code} - {response.text}")
                
                # Step 3: Import regions
                log_info("Importing regions...")
                regions_file = WORKSPACE / "samples" / "norway" / "regions" / "norway-regions-2024.csv"
                
                if not regions_file.exists():
                    log_error(f"Regions file not found: {regions_file}")
                    return False
                
                with open(regions_file, 'r') as f:
                    csv_content = f.read()
                    
                    # Use the REST endpoint for direct batch insert of regions
                    response = session.post(
                        api_url("/rest/region_upload"),
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code in (200, 201):
                        log_success("Uploaded regions successfully")
                    else:
                        log_warning(f"Failed to upload regions: {response.status_code} - {response.text}")
                
                # Step 4: Import sectors
                log_info("Importing sectors...")
                sectors_file = WORKSPACE / "samples" / "norway" / "sector" / "sector_norway.csv"
                
                if not sectors_file.exists():
                    log_error(f"Sectors file not found: {sectors_file}")
                    return False
                
                with open(sectors_file, 'r') as f:
                    csv_content = f.read()
                    
                    # Use the REST endpoint for direct batch insert of sectors
                    response = session.post(
                        api_url("/rest/sector_custom_only"),
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code in (200, 201):
                        log_success("Uploaded sectors successfully")
                    else:
                        log_warning(f"Failed to upload sectors: {response.status_code} - {response.text}")
                
                # Step 5: Import legal forms
                log_info("Importing legal forms...")
                legal_forms_file = WORKSPACE / "samples" / "norway" / "legal_form" / "legal_form_norway.csv"
                
                if not legal_forms_file.exists():
                    log_error(f"Legal forms file not found: {legal_forms_file}")
                    return False
                
                with open(legal_forms_file, 'r') as f:
                    csv_content = f.read()
                    
                    # Use the REST endpoint for direct batch insert of legal forms
                    response = session.post(
                        api_url("/rest/legal_form_custom_only"),
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code in (200, 201):
                        log_success("Uploaded legal forms successfully")
                    else:
                        log_warning(f"Failed to upload legal forms: {response.status_code} - {response.text}")
                
                # Verify setup was completed
                categories = api_request(session, "GET", "/rest/activity_category_enabled_custom?limit=1")
                if categories and len(categories) > 0:
                    log_success("Norway setup completed successfully")
                else:
                    log_warning("Norway setup may not have completed successfully")
        except Exception as e:
            log_warning(f"Error during Norway setup: {e}")
        
        # Setup import definitions
        if not setup_import_definitions(session):
            log_error("Failed to set up import definitions")
            return False
        
        # Create import jobs
        if not create_import_jobs(session):
            log_error("Failed to create import jobs")
            return False
        
        # Upload data files
        if not upload_data_files(session):
            log_error("Failed to upload data files")
            return False
        
        if args.isolated:
            # No app, so no SSE status stream: the worker runs until every queue is idle.
            if not isolated_run_worker():
                log_error("Worker did not finish the import and derive cleanly")
                return False
            jobs = api_request(session, "GET", "/rest/import_job?slug=like.import_*_sht&select=slug,state")
            not_finished = [j for j in (jobs or []) if j["state"] != "finished"]
            if not jobs or not_finished:
                log_error(f"Import jobs not finished: {not_finished or 'none found'}")
                return False
            log_success(f"All {len(jobs)} import jobs finished")
        else:
            # Wait for background processing of import jobs
            if not wait_for_worker_processing_of_import_jobs(session):
                log_error("Failed to process import jobs")
                return False

            # Wait for worker to finish deriving statistical units and reports
            if not wait_for_worker_derive(session):
                log_warning("Failed to wait for worker derivation to complete")
                # Continue anyway as this is not critical
        
        # Verify imported data
        if not verify_imported_data(session):
            log_error("Failed to verify imported data")
            return False
        if args.isolated and not isolated_verify_history():
            log_error("History does not match statistical_unit")
            return False
        
        # Print summary
        print(f"\n{GREEN}=== Norway Small History Import Test Completed Successfully ==={NC}\n")
        return True
    
    elif action == "delete":
        # Delete imported data
        if not delete_imported_data(session):
            log_error("Failed to delete imported data")
            return False
        
        # Print summary
        print(f"\n{GREEN}=== Norway Small History Cleanup Completed Successfully ==={NC}\n")
        return True
    return False

if __name__ == "__main__":
    sys.exit(0 if main() else 1)
