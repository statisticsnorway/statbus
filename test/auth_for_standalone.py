#!/usr/bin/env python3
"""
Test script for authentication in standalone mode
Tests both API access and direct database access with the same credentials
Run with `./test/auth_for_standalone.sh` that uses venv.
"""

import os
import atexit
import sys
import json
import time
import subprocess
import tempfile
import requests
import psycopg2
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any, Union
from requests.sessions import Session
import threading
import queue

# Colors for output
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

# Global flag to track if any problem was reproduced
PROBLEM_REPRODUCED_FLAG = False

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
# Extract host and port from CADDY_HTTP_BIND_ADDRESS
caddy_bind = os.environ["CADDY_HTTP_BIND_ADDRESS"]
caddy_host, caddy_port = caddy_bind.split(":")
CADDY_BASE_URL = f"http://{caddy_host}:{caddy_port}"
DB_HOST = "127.0.0.1"
DB_PORT = os.environ["DB_PUBLIC_LOCALHOST_PORT"]
DB_NAME = os.environ["POSTGRES_APP_DB"]

# Test users from setup.sql
ADMIN_EMAIL = "test.admin@statbus.org"
ADMIN_PASSWORD = "Admin#123!"
REGULAR_EMAIL = "test.regular@statbus.org"
REGULAR_PASSWORD = "Regular#123!"
RESTRICTED_EMAIL = "test.restricted@statbus.org"
RESTRICTED_PASSWORD = "Restricted#123!"

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

def log_problem_reproduced(message: str):
    """Flags that a specific problem being tested for has been reproduced."""
    global PROBLEM_REPRODUCED_FLAG
    PROBLEM_REPRODUCED_FLAG = True
    print(f"{RED}PROBLEM REPRODUCED: {message}{NC}")

def log_problem_identified(message: str) -> None:
    """Print a message indicating a known problem has been identified/reproduced locally."""
    print(f"{YELLOW}PROBLEM IDENTIFIED: {message}{NC}")


class LocalLogCollector:
    def __init__(self, services: list[str], log_queue: queue.Queue, compose_project_name: Optional[str] = None):
        self.services = services
        self.log_queue = log_queue
        self.compose_project_name = compose_project_name or os.environ.get("COMPOSE_PROJECT_NAME")
        self.process: Optional[subprocess.Popen] = None
        self.stdout_thread: Optional[threading.Thread] = None
        self.stderr_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    def _reader_thread_target(self, pipe, stream_name):
        try:
            for line in iter(pipe.readline, ''):
                if self._stop_event.is_set():
                    break
                self.log_queue.put(f"[Docker {stream_name}] {line.strip()}")
            pipe.close()
        except Exception as e:
            self.log_queue.put(f"[Docker {stream_name} ERROR] Exception in reader thread: {e}")

    def start(self):
        self._stop_event.clear()
        
        cmd_base = ["docker", "compose"]
        if self.compose_project_name:
            cmd_base.extend(["-p", self.compose_project_name])
        
        cmd = cmd_base + ["logs", "--follow", "--since", "1s"] + self.services
        
        log_info(f"Starting local log collection: {' '.join(cmd)}")
        try:
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1, # Line-buffered
                errors='replace',
                cwd=WORKSPACE # Ensure docker compose runs from project root
            )
        except FileNotFoundError:
            self.log_queue.put(f"[LOCAL ERROR] docker command not found. Ensure docker is installed and in PATH.")
            return
        except Exception as e:
            self.log_queue.put(f"[LOCAL ERROR] Failed to start docker compose logs process: {e}")
            return

        if self.process.stdout:
            self.stdout_thread = threading.Thread(target=self._reader_thread_target, args=(self.process.stdout, "stdout"))
            self.stdout_thread.daemon = True
            self.stdout_thread.start()

        if self.process.stderr:
            self.stderr_thread = threading.Thread(target=self._reader_thread_target, args=(self.process.stderr, "stderr"))
            self.stderr_thread.daemon = True
            self.stderr_thread.start()
        
        time.sleep(1) # Give logs a moment to start streaming

    def stop(self):
        log_info(f"Stopping local log collection for services: {', '.join(self.services)}...")
        self._stop_event.set()

        if self.process:
            if self.process.poll() is None:
                try:
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        log_warning(f"Local log collector process did not terminate gracefully, killing.")
                        self.process.kill()
                        try:
                            self.process.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            log_error(f"Failed to kill local log collector process.")
                except Exception as e:
                    log_warning(f"Error terminating local log collector process: {e}")
            self.process = None

        if self.stdout_thread and self.stdout_thread.is_alive():
            self.stdout_thread.join(timeout=2)
        if self.stderr_thread and self.stderr_thread.is_alive():
            self.stderr_thread.join(timeout=2)
        log_info("Local log collection stopped.")

def run_psql_command(query: str, user: str = None, password: str = None) -> str:
    """Run a PostgreSQL query and return the output"""
    env = os.environ.copy()
    if password:
        env["PGPASSWORD"] = password
    
    # Ensure the query is properly quoted and has a semicolon at the end
    if not query.strip().endswith(';'):
        query = query.strip() + ';'
    
    # Use a temporary file for the query to avoid command line escaping issues
    with tempfile.NamedTemporaryFile(mode='w+', suffix='.sql', delete=False) as temp_file:
        temp_file.write(query)
        temp_file_path = temp_file.name
    
    try:
        cmd = [
            "psql",
            "-h", DB_HOST,
            "-p", DB_PORT,
            "-d", DB_NAME,
            "-t",  # Tuple only output
            "-f", temp_file_path  # Use file input instead of -c
        ]
        
        if user:
            cmd.extend(["-U", user])
        
        debug_info(f"Running psql command with query file: {' '.join(cmd)}")
        debug_info(f"Query in file: {query}")
        debug_info(f"Using password: {'Yes' if password else 'No'}")
        debug_info(f"Environment variables: PGHOST={env.get('PGHOST')}, PGPORT={env.get('PGPORT')}, PGDATABASE={env.get('PGDATABASE')}, PGPASSWORD={'set' if password else 'not set'}")
        
        # Make sure we're passing the environment with PGPASSWORD to the subprocess
        result = subprocess.run(
            cmd,
            env=env,  # This passes the environment with PGPASSWORD
            check=True,
            capture_output=True,
            text=True,
            timeout=10  # Add 10 second timeout
        )
        debug_info(f"psql command succeeded with stdout: {repr(result.stdout)}")
        return result.stdout.strip()
    except subprocess.TimeoutExpired as e:
        debug_info(f"psql command timed out after 10 seconds: {e}")
        return "ERROR: Command timed out after 10 seconds. This might indicate connection issues or password prompts."
    except subprocess.CalledProcessError as e:
        debug_info(f"psql command failed with exit code {e.returncode}: {e}")
        debug_info(f"Command: {' '.join(cmd)}")
        debug_info(f"stderr: {repr(e.stderr)}")
        debug_info(f"stdout: {repr(e.stdout)}")
        return e.stderr
    finally:
        # Clean up the temporary file
        try:
            os.unlink(temp_file_path)
        except Exception as e:
            debug_info(f"Failed to delete temporary file {temp_file_path}: {e}")

def initialize_test_environment() -> None:
    """Initialize the test environment"""
    log_info("Initializing test environment...")
    print("Loading test users from setup.sql...")
    
    # Create tmp directory if it doesn't exist
    (WORKSPACE / "tmp").mkdir(exist_ok=True)
    
    # Check if API is reachable
    try:
        response = requests.get(CADDY_BASE_URL, timeout=5)
        log_info(f"API server is reachable. Status: {response.status_code}")
    except requests.RequestException as e:
        log_warning(f"API server might not be running: {e}")
        log_info("Make sure Caddy is running and listening on the correct port")
    
    # Check if database is reachable
    try:
        # Use pg_isready to check the database can be reached - without requiring a login
        debug_info(f"Checking database connection to {DB_HOST}:{DB_PORT}/{DB_NAME}")
        
        # Use a timeout to prevent hanging
        process = subprocess.run(
            ["pg_isready", "-h", DB_HOST, "-p", DB_PORT, "-d", DB_NAME],
            capture_output=True,
            text=True,
            check=False,  # Don't fail if this doesn't work
            timeout=5     # Add 5 second timeout
        )
        
        if process.returncode == 0:
            log_info(f"Database is reachable at {DB_HOST}:{DB_PORT}/{DB_NAME}")
            debug_info(f"pg_isready output: {process.stdout.strip()}")
        else:
            log_warning(f"Database might not be accessible: {process.stderr.strip()}")
            debug_info(f"Command: pg_isready -h {DB_HOST} -p {DB_PORT} -d {DB_NAME}")
    except subprocess.TimeoutExpired:
        log_warning(f"Database connection check timed out after 5 seconds")
        debug_info(f"This might indicate connection issues or password prompts")
    except Exception as e:
        log_warning(f"Failed to check database connection: {e}")
    
    # Run setup.sql
    setup_sql_path = WORKSPACE / "test" / "setup.sql"
    debug_info(f"Running setup SQL from: {setup_sql_path}")
    try:
        # Read the file as text, not bytes, since text=True is set in subprocess.run
        with open(setup_sql_path, 'r') as f:
            setup_sql = f.read()
            
        result = subprocess.run(
            [str(WORKSPACE / "devops" / "manage-statbus.sh"), "psql"],
            input=setup_sql,
            capture_output=True,
            text=True,
            check=True,
            timeout=15  # Add 15 second timeout
        )
        debug_info(f"Setup SQL output: {result.stdout}")
    except subprocess.TimeoutExpired:
        log_warning(f"Setup SQL execution timed out after 15 seconds")
        debug_info(f"This might indicate connection issues or the script is taking too long")
    except subprocess.CalledProcessError as e:
        log_warning(f"Setup SQL might have issues: {e}")
        debug_info(f"Setup SQL stderr: {e.stderr}")

def test_api_login(session: Session, email: str, password: str, expected_role: str) -> Optional[int]:
    """Test API login and return user ID if successful"""
    log_info(f"Testing API login for {email} (expected role: {expected_role})...")
    
    # Make login request
    try:
        debug_info(f"Sending login request to {CADDY_BASE_URL}/rest/rpc/login")
        debug_info(f"Request payload: {{'email': '{email}', 'password': '********'}}")
        
        response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/login",
            json={"email": email, "password": password},
            headers={"Content-Type": "application/json"}
        )
        
        debug_info(f"Response status code: {response.status_code}")
        debug_info(f"Response headers: {dict(response.headers)}")
        debug_info(f"Cookies after login: {session.cookies}")
        
        # Check if response is not successful
        if response.status_code != 200:
            def print_response_debug_info():
                print(f"Response body: {response.text}")
                print(f"API endpoint: {CADDY_BASE_URL}/rest/rpc/login")
            
            log_error(f"API login failed for {email}. Status code: {response.status_code}", print_response_debug_info)
            return None
        
        # Debug: Print raw response body
        debug_info(f"Raw response body: {repr(response.text)}")
        debug_info(f"Response content type: {response.headers.get('Content-Type', 'unknown')}")
        
        # Try to parse response
        try:
            # Handle empty response case
            if not response.text or response.text.strip() == "":
                def print_endpoint_info():
                    print(f"API endpoint: {CADDY_BASE_URL}/rest/rpc/login")
                
                log_error(f"API login failed for {email}. Empty response from server.", print_endpoint_info)
                return None
                
            data = response.json()
            debug_info(f"Login response: {json.dumps(data, indent=2)}")
        except json.JSONDecodeError as e:
            def print_response_details():
                print(f"Response text: {response.text!r}")  # Use repr to show whitespace/control chars
                print(f"Response headers: {dict(response.headers)}")
                print(f"API endpoint: {CADDY_BASE_URL}/rest/rpc/login")
            
            log_error(f"Failed to parse JSON response: {e}", print_response_details)
            return None
        
        # Check if login was successful
        if data.get("statbus_role") == expected_role:
            log_success(f"API login successful for {email}")
            
            # Verify cookies were set
            if session.cookies:
                log_success("Auth cookies were set correctly")
            else:
                log_error("Auth cookies were not set")
            
            # Return the user ID for further tests
            return data.get("uid")
        else:
            def print_login_failure_details():
                print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
                print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/login{NC}")
                print(f"{RED}Expected role: {expected_role}, Got: {data.get('statbus_role')}{NC}")
            
            log_error(f"API login failed for {email}.", print_login_failure_details)
            return None
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
        return None
    except json.JSONDecodeError:
        log_error(f"Invalid JSON response from server")
        print(f"{RED}Response text: {response.text}{NC}")
        return None

def test_api_access(session: Session, email: str, endpoint: str, expected_status: int) -> None:
    """Test API access with authenticated user"""
    log_info(f"Testing API access to {endpoint} for {email} (expected status: {expected_status})...")
    
    # Make authenticated request
    try:
        response = session.get(
            f"{CADDY_BASE_URL}{endpoint}",
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == expected_status:
            log_success(f"API access to {endpoint} returned expected status {expected_status}")
        else:
            def print_api_access_details():
                print(f"{RED}Response body:{NC}")
                print(response.text)
                print(f"{RED}API endpoint: {CADDY_BASE_URL}{endpoint}{NC}")
            
            log_error(f"API access to {endpoint} returned status {response.status_code}, expected {expected_status}", 
                     print_api_access_details)
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")

def test_db_access(email: str, password: str, query: str, expected_result: str) -> None:
    """Test direct database access"""
    log_info(f"Testing direct database access for {email}...")
    
    # Build the psql command for debugging - using echo to pipe the query to psql
    # This is more reliable than using -c with complex queries
    psql_cmd = f"echo \"{query}\" | psql -h {DB_HOST} -p {DB_PORT} -d {DB_NAME} -U {email}"
    debug_info(f"Command to run manually: PGPASSWORD='{password}' {psql_cmd}")
    
    # First check if we can connect and verify the current user matches the email
    user_check = run_psql_command("SELECT current_user;", email, password)
    debug_info(f"User check result: {repr(user_check)}")
    
    # If user check fails, report the error
    if email not in user_check:
        def print_db_debug_info():
            print(f"{RED}User check failed{NC}")
            print(f"{RED}Result: {user_check}{NC}")
            print(f"{RED}Connection: {email}@{DB_HOST}:{DB_PORT}/{DB_NAME}{NC}")
            print(f"{RED}Manual command to try: PGPASSWORD='{password}' psql -h {DB_HOST} -p {DB_PORT} -d {DB_NAME} -U {email} -c \"SELECT current_user;\"{NC}")
                
            # Try to get more diagnostic information
            debug_info("Checking if the user role exists in the database...")
            role_check = subprocess.run(
                [str(WORKSPACE / "devops" / "manage-statbus.sh"), "psql", "-c", f"SELECT rolname FROM pg_roles WHERE rolname = '{email}';"],
                capture_output=True,
                text=True,
                check=False,
                timeout=5
            )
            debug_info(f"Role check result: {role_check.stdout}")
                
            if email in role_check.stdout:
                debug_info(f"Role '{email}' exists in the database")
            else:
                debug_info(f"Role '{email}' does NOT exist in the database")
            
        log_error(f"Database connection failed for {email}.", print_db_debug_info)
        return
    
    # User check passed, now execute the actual query
    debug_info(f"User check passed, executing query: {query}")
    result = run_psql_command(query, email, password)
    debug_info(f"Raw psql output: {repr(result)}")
    
    # Check if query was successful and returned expected result
    import re
    
    if re.search(expected_result, result):
        log_success(f"Database access successful for {email}")
    else:
        def print_query_debug_info():
            print(f"{RED}Query: {query}{NC}")
            print(f"{RED}Result: '{result}'{NC}")
            print(f"{RED}Expected to match: {expected_result}{NC}")
            print(f"{RED}Connection: {email}@{DB_HOST}:{DB_PORT}/{DB_NAME}{NC}")
            print(f"{RED}Manual command to try: PGPASSWORD='{password}' {psql_cmd}{NC}")
        
        log_error(f"Database access failed for {email}.", print_query_debug_info)

def test_api_logout(session: Session) -> None:
    """Test API logout"""
    log_info("Testing API logout...")
    
    # Store the number of cookies before logout
    cookies_before = len(session.cookies)
    
    # Make logout request
    try:
        response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/logout",
            headers={"Content-Type": "application/json"}
        )
        
        # Check if logout was successful
        data = response.json()
        if response.status_code == 200 and data.get("is_authenticated") is False:
            log_success("API logout successful")
            
            # Verify cookies were cleared
            # When cookies are cleared, they're set with empty values or past expiration
            # The response will contain Set-Cookie headers, but the cookie jar might be empty
            # because the browser would delete them
            
            # Check if the response contains Set-Cookie headers that clear cookies
            cleared_headers = any(
                cookie.value == "" or 
                (hasattr(cookie, 'expires') and cookie.expires == 0) or
                'Expires=Thu, 01 Jan 1970' in response.headers.get('Set-Cookie', '')
                for cookie in response.cookies
            )
            
            cookies_after = len(session.cookies)
            
            if cleared_headers or cookies_after < cookies_before:
                log_success("Auth cookies were cleared correctly")
            else:
                log_warning("Auth cookies might not have been properly cleared")
                print(f"{YELLOW}Session cookies: {session.cookies}{NC}")
        else:
            log_error("API logout failed.")
            print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
            print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/logout{NC}")
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
    except json.JSONDecodeError:
        log_error(f"Invalid JSON response from server")
        print(f"{RED}Response text: {response.text}{NC}")

def test_token_refresh(session: Session, email: str, password: str) -> None:
    """Test token refresh"""
    log_info(f"Testing token refresh for {email}...")
    
    # First login to get initial tokens
    test_api_login(session, email, password, "admin_user")
    
    # Store initial cookies for comparison
    initial_cookies = {cookie.name: cookie.value for cookie in session.cookies}
    
    # Sleep 1 second to ensure the iat will increase
    time.sleep(1)
    
    # Make refresh request
    try:
        response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/refresh",
            headers={"Content-Type": "application/json"}
        )
        
        # Check if refresh was successful
        data = response.json()
        if response.status_code == 200 and data.get("is_authenticated") is True:
            log_success(f"Token refresh successful for {email}")
            
            # Get new cookies for comparison
            new_cookies = {cookie.name: cookie.value for cookie in session.cookies}
            
            # Verify tokens were updated
            access_cookie_name = "statbus"
            refresh_cookie_name = "statbus-refresh"
            
            if (access_cookie_name in new_cookies and 
                access_cookie_name in initial_cookies and
                new_cookies[access_cookie_name] != initial_cookies[access_cookie_name]):
                log_success("Access token was updated")
            else:
                log_warning("Access token might not have been updated")
            
            if (refresh_cookie_name in new_cookies and 
                refresh_cookie_name in initial_cookies and
                new_cookies[refresh_cookie_name] != initial_cookies[refresh_cookie_name]):
                log_success("Refresh token was updated")
            else:
                log_warning("Refresh token might not have been updated")
        else:
            log_error("Token refresh failed.")
            print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
            print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/refresh{NC}")
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
    except json.JSONDecodeError:
        log_error(f"Invalid JSON response from server")
        print(f"{RED}Response text: {response.text}{NC}")

def test_auth_status(session: Session, expected_auth: bool) -> None:
    """Test auth status"""
    log_info(f"Testing auth status (expected authenticated: {expected_auth})...")
        
    # Make auth status request
    try:
        debug_info(f"Session cookies before request: {session.cookies}")
        response = session.get(
            f"{CADDY_BASE_URL}/rest/rpc/auth_status",
            headers={"Content-Type": "application/json"}
        )
        
        debug_info(f"Auth status response code: {response.status_code}")
        debug_info(f"Auth status response headers: {dict(response.headers)}")
        debug_info(f"Auth status raw response: {response.text}")
        
        # Check if auth status matches expectation
        try:
            data = response.json()
            debug_info(f"Auth status parsed response: {json.dumps(data, indent=2)}")
                
            if data.get("is_authenticated") == expected_auth:
                log_success(f"Auth status returned expected authentication state: {expected_auth}")
            else:
                def print_auth_status_details():
                    print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
                    print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/auth_status{NC}")
                    print(f"{RED}Expected is_authenticated: {expected_auth}{NC}")
                
                log_error(f"Auth status did not return expected authentication state.", print_auth_status_details)
        except json.JSONDecodeError as e:
            def print_auth_status_response_details():
                print(f"{RED}Response text: {response.text!r}{NC}")
                print(f"{RED}Response status: {response.status_code}{NC}")
                print(f"{RED}Response headers: {dict(response.headers)}{NC}")
            
            log_error(f"Invalid JSON response from auth_status: {e}", print_auth_status_response_details)
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")

def test_bearer_token_auth(email: str, password: str) -> None:
    """Test API access using Bearer token in Authorization header"""
    log_info(f"Testing API access with Bearer token for {email}...")
    
    # First, get the token by logging in
    session = requests.Session()
    try:
        login_response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/login",
            json={"email": email, "password": password},
            headers={"Content-Type": "application/json"}
        )
        
        if login_response.status_code != 200:
            log_error(f"Failed to get token: Login failed with status {login_response.status_code}")
            return
        
        login_data = login_response.json()
        # The login endpoint sets cookies but doesn't return the token in the body.
        # We need to get the token from the auth_test endpoint or cookies.
        
        # Call auth_test to get the actual token string from the cookies field in its response
        auth_test_response = session.get(
            f"{CADDY_BASE_URL}/rest/rpc/auth_test",
            headers={"Content-Type": "application/json"}
        )
        if auth_test_response.status_code != 200:
            log_error(f"Failed to get auth_test details to retrieve token. Status: {auth_test_response.status_code}, Body: {auth_test_response.text}")
            return
        
        auth_test_data = auth_test_response.json()
        access_token = auth_test_data.get("cookies", {}).get("statbus")

        if not access_token:
            log_error("Failed to get access token from auth_test response cookies")
            debug_info(f"Auth_test response for token retrieval: {json.dumps(auth_test_data, indent=2)}")
            return
        
        debug_info(f"Got access token via auth_test: {access_token[:20]}...")
        session.close() # Close the session as we are done with it for this part of the test.

        # Test 1: Verify auth_status endpoint with Bearer token
        log_info("Testing auth_status endpoint with Bearer token...")
        auth_status_response = requests.get(
            f"{CADDY_BASE_URL}/rest/rpc/auth_status",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            }
        )
        
        debug_info(f"Bearer auth_status response code: {auth_status_response.status_code}")
        debug_info(f"Bearer auth_status response headers: {dict(auth_status_response.headers)}")
        
        if auth_status_response.status_code == 200:
            try:
                auth_data = auth_status_response.json()
                if auth_data.get("is_authenticated") is True:
                    log_success(f"Auth status with Bearer token shows authenticated user")
                    debug_info(f"Auth status response: {json.dumps(auth_data, indent=2)}")
                else:
                    def print_auth_status_details():
                        print(f"{RED}Response: {json.dumps(auth_data, indent=2)}{NC}")
                        print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/auth_status{NC}")
                        print(f"{RED}Expected is_authenticated: True{NC}")
                    
                    log_error(f"Auth status with Bearer token shows unauthenticated user", print_auth_status_details)
            except json.JSONDecodeError as e:
                def print_auth_status_response_details():
                    print(f"{RED}Response text: {auth_status_response.text!r}{NC}")
                    print(f"{RED}Response status: {auth_status_response.status_code}{NC}")
                
                log_error(f"Invalid JSON response from auth_status with Bearer token: {e}", print_auth_status_response_details)
        else:
            def print_auth_status_error_details():
                print(f"{RED}Response status: {auth_status_response.status_code}{NC}")
                print(f"{RED}Response text: {auth_status_response.text}{NC}")
                print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/auth_status{NC}")
            
            log_error(f"Auth status with Bearer token failed", print_auth_status_error_details)
        
        # Test 2: Verify data access endpoint with Bearer token
        log_info("Testing data access endpoint with Bearer token...")
        bearer_response = requests.get(
            f"{CADDY_BASE_URL}/rest/country?limit=5",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            }
        )
        
        debug_info(f"Bearer auth response code: {bearer_response.status_code}")
        debug_info(f"Bearer auth response headers: {dict(bearer_response.headers)}")
        
        if bearer_response.status_code == 200:
            # Try to parse the response to verify it's valid
            try:
                data = bearer_response.json()
                if isinstance(data, list) and len(data) > 0:
                    log_success(f"API access with Bearer token successful")
                else:
                    log_warning(f"API access with Bearer token returned empty result")
            except json.JSONDecodeError as e:
                def print_bearer_response_details():
                    print(f"{RED}Response text: {bearer_response.text!r}{NC}")
                
                log_error(f"Invalid JSON response from Bearer token request: {e}", print_bearer_response_details)
        else:
            def print_bearer_error_details():
                print(f"{RED}Response status: {bearer_response.status_code}{NC}")
                print(f"{RED}Response text: {bearer_response.text}{NC}")
                print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/region?limit=5{NC}")
                print(f"{RED}Authorization header: Bearer {access_token[:10]}...{NC}")
            
            log_error(f"API access with Bearer token failed", print_bearer_error_details)
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
    except json.JSONDecodeError as e:
        log_error(f"Invalid JSON response: {e}")


def test_api_key_management(session: Session, email: str, password: str) -> None:
    """Test API key creation, listing, usage, and revocation"""
    log_info(f"Testing API Key Management for {email}...")

    # 1. Login to get access token/cookies
    user_id = test_api_login(session, email, password, "regular_user") # Assuming regular user can create keys
    if not user_id:
        log_error("Login failed, cannot proceed with API key tests")
        return

    # 2. Create API Key
    log_info("Creating API key...")
    key_description = "Test Script Key"
    key_duration = "1 day" # Use a short duration for testing
    api_key_jwt = None
    key_jti = None
    try:
        response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/create_api_key",
            json={"description": key_description, "duration": key_duration},
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200:
            response_data = response.json()
            api_key_jwt = response_data['token']
            key_jti = response_data['jti']  # Get JTI directly from response
            log_success("API key created successfully")
            debug_info(f"API key JWT: {api_key_jwt[:20]}...")
            debug_info(f"API key JTI: {key_jti}")
        else:
            log_error(f"Failed to create API key. Status: {response.status_code}, Body: {response.text}")
            return
    except requests.RequestException as e:
        log_error(f"API request failed during key creation: {e}")
        return
    except json.JSONDecodeError:
         log_error(f"Invalid JSON response during key creation: {response.text}")
         return

    # 3. Create a second API Key with different description
    log_info("Creating a second API key with different description...")
    second_key_description = "Second Test Key"
    second_api_key_jwt = None
    try:
        response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/create_api_key",
            json={"description": second_key_description, "duration": key_duration},
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200:
            response_data = response.json()
            second_api_key_jwt = response_data['token']
            log_success("Second API key created successfully")
            debug_info(f"Second API key JWT: {second_api_key_jwt[:20]}...")
        else:
            log_warning(f"Failed to create second API key. Status: {response.status_code}, Body: {response.text}")
    except Exception as e:
        log_warning(f"Error creating second API key: {e}")
    
    # 4. List API Keys and find the new ones
    log_info("Listing API keys...")
    listed_keys = []
    try:
        # Query the api_key table directly instead of using a function
        response = session.get(
            f"{CADDY_BASE_URL}/rest/api_key",
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200:
            listed_keys = response.json()
            debug_info(f"Found {len(listed_keys)} API keys")
            
            # Find our test keys
            found_key = None
            second_key = None
            for key in listed_keys:
                if key.get("description") == key_description:
                    found_key = key
                    key_jti = key.get("jti")
                elif key.get("description") == second_key_description:
                    second_key = key
            
            if found_key and key_jti:
                log_success(f"Found newly created API key in list (JTI: {key_jti})")
                debug_info(f"Key details: {found_key}")
            else:
                log_error(f"Newly created API key not found in list. Keys: {listed_keys}")
                return
                
            if second_key:
                log_success(f"Found second API key in list (JTI: {second_key.get('jti')})")
                debug_info(f"Second key details: {second_key}")
            elif second_api_key_jwt:  # Only warn if we actually created a second key
                log_warning(f"Second API key not found in list")
        else:
            log_error(f"Failed to list API keys. Status: {response.status_code}, Body: {response.text}")
            return
    except requests.RequestException as e:
        log_error(f"API request failed during key listing: {e}")
        return
    except json.JSONDecodeError:
         log_error(f"Invalid JSON response during key listing: {response.text}")
         return

    # 5. Verify RLS: Log in as another user and check they cannot see the key
    log_info("Verifying RLS: Checking if another user can see the key...")
    test_api_logout(session) # Log out the current user (regular)
    other_session = requests.Session()
    other_user_email = RESTRICTED_EMAIL # Use restricted user for this check
    other_user_password = RESTRICTED_PASSWORD
    other_user_id = test_api_login(other_session, other_user_email, other_user_password, "restricted_user")
    if not other_user_id:
        log_error(f"Login failed for {other_user_email}, cannot proceed with RLS check")
        # Log back in as original user before returning
        test_api_login(session, email, password, "regular_user")
        return

    try:
        response = other_session.get(
            f"{CADDY_BASE_URL}/rest/api_key",
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200:
            other_keys = response.json()
            found_other_key = False
            for key in other_keys:
                if key.get("jti") == key_jti:
                    found_other_key = True
                    break
            if not found_other_key:
                log_success(f"RLS check passed: User {other_user_email} cannot see key {key_jti}")
            else:
                log_error(f"RLS check failed: User {other_user_email} could see key {key_jti}. Keys: {other_keys}")
        else:
            log_error(f"Failed to list API keys for {other_user_email}. Status: {response.status_code}, Body: {response.text}")
    except requests.RequestException as e:
        log_error(f"API request failed during RLS check key listing: {e}")
    except json.JSONDecodeError:
         log_error(f"Invalid JSON response during RLS check key listing: {response.text}")
    finally:
        # Log out the other user and log back in the original user
        test_api_logout(other_session)
        test_api_login(session, email, password, "regular_user") # Re-login original user

    # 6. Use API Key for Data Access
    log_info("Testing data access using the API key...")
    try:
        bearer_response = requests.get(
            f"{CADDY_BASE_URL}/rest/country?limit=1", # Use a simple endpoint
            headers={
                "Authorization": f"Bearer {api_key_jwt}",
                "Accept": "application/json" # Ensure correct accept header
            }
        )
        if bearer_response.status_code == 200:
            try:
                data = bearer_response.json()
                if isinstance(data, list):
                     log_success("API key successfully used for data access")
                else:
                     log_warning(f"API key access returned unexpected data format: {data}")
            except json.JSONDecodeError:
                 log_error(f"Invalid JSON response when using API key: {bearer_response.text}")
        else:
            log_error(f"API key access failed. Status: {bearer_response.status_code}, Body: {bearer_response.text}")
    except requests.RequestException as e:
        log_error(f"API request failed when using API key: {e}")

    # 7. Revoke API Key
    log_info(f"Revoking API key (JTI: {key_jti})...")
    try:
        response = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/revoke_api_key",
            json={"key_jti": key_jti},
            headers={"Content-Type": "application/json"}
        )
        # revoke_api_key returns boolean true/false in the body
        if response.status_code == 200 and response.json() is True:
            log_success("API key revoked successfully")
        else:
            log_error(f"Failed to revoke API key. Status: {response.status_code}, Body: {response.text}")
            # Don't return here, try accessing with revoked key anyway
    except requests.RequestException as e:
        log_error(f"API request failed during key revocation: {e}")
    except json.JSONDecodeError:
         log_error(f"Invalid JSON response during key revocation: {response.text}")

    # 8. Verify key is marked as revoked in listing
    log_info("Verifying key is marked as revoked in listing...")
    try:
        response = session.get(
            f"{CADDY_BASE_URL}/rest/api_key",
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200:
            listed_keys = response.json()
            revoked_key = None
            for key in listed_keys:
                if key.get("jti") == key_jti:
                    revoked_key = key
                    break
            
            if revoked_key and revoked_key.get("revoked_at") is not None:
                log_success(f"API key correctly shows as revoked in listing")
                debug_info(f"Revoked key details: {revoked_key}")
            else:
                log_error(f"API key does not show as revoked in listing: {revoked_key}")
        else:
            log_error(f"Failed to list API keys after revocation. Status: {response.status_code}")
    except Exception as e:
        log_error(f"Error checking revoked key status: {e}")

    # 9. Attempt to Use Revoked API Key
    log_info("Attempting data access with revoked API key...")
    try:
        bearer_response = requests.get(
            f"{CADDY_BASE_URL}/rest/country?limit=1",
            headers={
                "Authorization": f"Bearer {api_key_jwt}",
                "Accept": "application/json"
            }
        )
        # API returns 400 with "API Key has been revoked" message
        if bearer_response.status_code == 400 and 'API Key has been revoked' in bearer_response.text:
            log_success(f"Access correctly denied for revoked API key (Status: 400, Error: Revoked)")
            debug_info(f"Response body: {bearer_response.text}")
        else:
            log_error(f"Access with revoked API key returned unexpected status: {bearer_response.status_code}, Body: {bearer_response.text}")
    except requests.RequestException as e:
        log_error(f"API request failed when using revoked API key: {e}")

    # 10. Test API key with invalid JTI
    if second_api_key_jwt:
        log_info("Testing API key with non-existent JTI...")
        # Create a modified JWT with a non-existent JTI
        # This is a simplified approach - in a real test we'd properly decode/modify/re-encode
        # For now, just use the second key but modify the Authorization header
        try:
            tampered_response = requests.get(
                f"{CADDY_BASE_URL}/rest/country?limit=1",
                headers={
                    "Authorization": f"Bearer {second_api_key_jwt.replace('.', '.INVALID.')}",
                    "Accept": "application/json"
                }
            )
            if tampered_response.status_code in (401, 403, 500):
                log_success(f"Access correctly denied for tampered API key (Status: {tampered_response.status_code})")
                debug_info(f"Response body: {tampered_response.text}")
            else:
                log_error(f"Access with tampered API key returned unexpected status: {tampered_response.status_code}")
        except Exception as e:
            log_error(f"Error testing tampered API key: {e}")

    log_info(f"API Key Management test for {email} completed.")


def test_password_change(admin_session: Session, user_session: Session, user_email: str, initial_password: str) -> None:
    """Test user and admin password changes and session invalidation"""
    log_info(f"Testing Password Change for {user_email}...")
    new_password = initial_password + "_new"

    # 0. Ensure admin is logged in for later use
    admin_id = test_api_login(admin_session, ADMIN_EMAIL, ADMIN_PASSWORD, "admin_user")
    if not admin_id:
        log_error("Admin login failed, cannot proceed with password change tests")
        return

    # 1. Login user to establish a session
    expected_role = "restricted_user" if user_email == RESTRICTED_EMAIL else "regular_user"
    user_id = test_api_login(user_session, user_email, initial_password, expected_role)
    if not user_id:
        log_error("Initial login failed, cannot proceed with password change tests")
        return
    # Store the refresh token cookie value (requests session handles cookies automatically)
    initial_refresh_cookie = user_session.cookies.get("statbus-refresh")
    if not initial_refresh_cookie:
         log_warning("Could not get refresh token cookie after initial login")

    # 2. User changes their own password
    log_info("User changing their own password...")
    try:
        response = user_session.post(
            f"{CADDY_BASE_URL}/rest/rpc/change_password",
            json={"new_password": new_password},
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200 and response.json() is True:
            log_success("User password change successful")
        else:
            log_error(f"User password change failed. Status: {response.status_code}, Body: {response.text}")
            return # Stop if this fails
    except requests.RequestException as e:
        log_error(f"API request failed during user password change: {e}")
        return
    except json.JSONDecodeError:
         log_error(f"Invalid JSON response during user password change: {response.text}")
         return

    # 3. Verify old password fails
    log_info("Verifying login with old password fails...")
    temp_session_old = requests.Session()
    try:
        response = temp_session_old.post(
            f"{CADDY_BASE_URL}/rest/rpc/login",
            json={"email": user_email, "password": initial_password},
            headers={"Content-Type": "application/json"}
        )
        
        data = response.json()
        # Check if login failed as expected (null values in response)
        if data.get("uid") is None and data.get("access_jwt") is None:
            log_success(f"Login correctly failed with old password after change")
        else:
            log_error(f"Login unexpectedly succeeded with old password after change")
    except requests.RequestException as e:
        log_error(f"API request failed during old password check: {e}")

    # 4. Verify new password works
    log_info("Verifying login with new password works...")
    temp_session_new = requests.Session()
    expected_role = "restricted_user" if user_email == RESTRICTED_EMAIL else "regular_user"
    test_api_login(temp_session_new, user_email, new_password, expected_role) # Expect success

    # 5. Verify old session refresh fails
    log_info("Verifying refresh with old session token fails...")
    if initial_refresh_cookie:
        # Manually set the old cookie in a new session to test refresh
        old_session = requests.Session()
        old_session.cookies.set("statbus-refresh", initial_refresh_cookie)
        try:
            response = old_session.post(
                f"{CADDY_BASE_URL}/rest/rpc/refresh",
                headers={"Content-Type": "application/json"}
            )
            # Expecting 401, 400 or similar error because the session was deleted
            if (response.status_code == 401 or 
                response.status_code == 400 or 
                (response.status_code == 500 and 'Invalid session' in response.text) or
                'Invalid session' in response.text or
                'token has been superseded' in response.text):
                log_success(f"Refresh correctly failed for invalidated session (Status: {response.status_code})")
            else:
                log_error(f"Refresh with invalidated session returned unexpected status: {response.status_code}, Body: {response.text}")
        except requests.RequestException as e:
            log_error(f"API request failed during invalidated refresh check: {e}")
    else:
        log_warning("Skipping old session refresh check as initial refresh cookie was not found.")

    # 6. Admin changes user's password back
    log_info("Admin changing user password back...")
    # Ensure admin session is still valid (or re-login)
    test_auth_status(admin_session, True)
    # Get user sub
    user_sub = None
    try:
        # Use psql to get sub reliably
        user_sub_str = run_psql_command(f"SELECT sub FROM auth.user WHERE email = '{user_email}';", ADMIN_EMAIL, ADMIN_PASSWORD)
        if user_sub_str and 'ERROR' not in user_sub_str:
            user_sub = user_sub_str.strip()
            debug_info(f"Got user sub for admin change: {user_sub}")
        else:
            log_error(f"Could not get user sub via psql: {user_sub_str}")
            return
    except Exception as e:
        log_error(f"Error getting user sub: {e}")
        return

    if not user_sub:
        log_error("Failed to retrieve user sub for admin password change.")
        return

    try:
        response = admin_session.post(
            f"{CADDY_BASE_URL}/rest/rpc/admin_change_password",
            json={"user_sub": user_sub, "new_password": initial_password},
            headers={"Content-Type": "application/json"}
        )
        if response.status_code == 200 and response.json() is True:
            log_success("Admin password change successful")
        else:
            log_error(f"Admin password change failed. Status: {response.status_code}, Body: {response.text}")
    except requests.RequestException as e:
        log_error(f"API request failed during admin password change: {e}")
    except json.JSONDecodeError:
         log_error(f"Invalid JSON response during admin password change: {response.text}")

    # 7. Verify user can log in with original password again
    log_info("Verifying login with original password works again...")
    final_session = requests.Session()
    expected_role = "restricted_user" if user_email == RESTRICTED_EMAIL else "regular_user"
    test_api_login(final_session, user_email, initial_password, expected_role) # Expect success

    log_info(f"Password Change test for {user_email} completed.")


def test_auth_test_endpoint(session: Session, logged_in: bool = False) -> None:
    """Test the auth_test endpoint to get detailed debug information"""
    log_info(f"Testing auth_test endpoint (logged in: {logged_in})...")

    log_q = queue.Queue()
    services_to_log = ["db", "proxy", "rest"]
    collector = LocalLogCollector(services_to_log, log_q)
    
    collector.start()
    
    try:
        # Test GET request
        response = session.get(
            f"{CADDY_BASE_URL}/rest/rpc/auth_test",
            headers={"Content-Type": "application/json"}
        )
        
        # Check if request was successful
        if response.status_code == 200:
            log_success(f"Auth test endpoint returned status 200")
            
            # Parse and print the response if in debug mode
            try:
                data = response.json()
                # PostgREST RPCs that return a single row might wrap it in an array
                actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data

                if os.environ.get("DEBUG"):
                    print(f"\n{YELLOW}=== Auth Test Response (GET, {logged_in=}) ==={NC}")
                    print(f"{YELLOW}{json.dumps(actual_data, indent=2)}{NC}\n")

                if logged_in:
                    # With SECURITY INVOKER, top-level 'claims' from current_setting might show 'anon'.
                    # Verify authentication using 'access_token.claims' which directly reflects the parsed token.
                    access_token_details = actual_data.get("access_token", {})
                    access_token_claims = access_token_details.get("claims", {})
                    user_email_in_token = access_token_claims.get("email")
                    
                    expected_email_for_session = (ADMIN_EMAIL if "admin" in session.headers.get("User-Agent", "") else
                                                  REGULAR_EMAIL if "regular" in session.headers.get("User-Agent", "") else
                                                  RESTRICTED_EMAIL if "restricted" in session.headers.get("User-Agent", "") else None)

                    if access_token_details.get("present") and user_email_in_token == expected_email_for_session:
                        log_success(f"GET /rpc/auth_test: 'access_token.claims.email' ({user_email_in_token}) correctly matches logged-in user ({expected_email_for_session}).")
                    elif access_token_details.get("present"):
                        log_problem_reproduced(f"GET /rpc/auth_test: 'access_token.claims.email' ({user_email_in_token}) does not match expected user ({expected_email_for_session}) although token is present. Token claims: {access_token_claims}")
                    else:
                        log_problem_reproduced(f"GET /rpc/auth_test: Access token not present in response for an expected logged-in session.")

                    # Informational: Log the top-level claims (from GUC) for debugging.
                    # Expect 'anon' or similar for the top-level claims role with SECURITY INVOKER entry point.
                    top_level_claims = actual_data.get("claims", {})
                    log_info(f"  GET /rpc/auth_test: Top-level 'claims' (from GUC) for this session: {json.dumps(top_level_claims)}")
                    if top_level_claims.get("role") != "anon": # This is the GUC value, which might be 'anon'
                        log_warning(f"  GET /rpc/auth_test: Top-level 'claims.role' (GUC) was '{top_level_claims.get('role')}', not 'anon' as potentially expected for SECURITY INVOKER entry point.")

                    # Verify current_db_user and current_db_role from the function's perspective
                    db_user = actual_data.get("current_db_user")
                    db_role = actual_data.get("current_db_role")
                    if db_user == expected_email_for_session:
                        log_success(f"  GET /rpc/auth_test: 'current_db_user' ({db_user}) matches expected authenticated user.")
                    else:
                        log_problem_reproduced(f"  GET /rpc/auth_test: 'current_db_user' ({db_user}) does not match expected authenticated user ({expected_email_for_session}).")
                    
                    if db_role == expected_email_for_session: # In PG, after SET ROLE, current_user is the role
                        log_success(f"  GET /rpc/auth_test: 'current_db_role' ({db_role}) matches expected authenticated role.")
                    else:
                        log_problem_reproduced(f"  GET /rpc/auth_test: 'current_db_role' ({db_role}) does not match expected authenticated role ({expected_email_for_session}).")

                elif not logged_in: # Unauthenticated
                    top_level_claims_role = actual_data.get("claims", {}).get("role")
                    db_user_unauth = actual_data.get("current_db_user")
                    db_role_unauth = actual_data.get("current_db_role")

                    if top_level_claims_role == "anon":
                        log_success("GET /rpc/auth_test: Top-level 'claims.role' (GUC) is 'anon' as expected for unauthenticated session.")
                    else:
                        log_warning(f"GET /rpc/auth_test: Top-level 'claims.role' (GUC) is '{top_level_claims_role}', expected 'anon'.")
                    
                    if db_user_unauth == "anon":
                        log_success(f"  GET /rpc/auth_test: 'current_db_user' is '{db_user_unauth}' as expected for unauthenticated session.")
                    else:
                        log_problem_reproduced(f"  GET /rpc/auth_test: 'current_db_user' is '{db_user_unauth}', expected 'anon'.")

                    if db_role_unauth == "anon":
                        log_success(f"  GET /rpc/auth_test: 'current_db_role' is '{db_role_unauth}' as expected for unauthenticated session.")
                    else:
                        log_problem_reproduced(f"  GET /rpc/auth_test: 'current_db_role' is '{db_role_unauth}', expected 'anon'.")

            except json.JSONDecodeError as e:
                def print_auth_test_response():
                    print(f"{RED}Response text (GET): {response.text!r}{NC}")
                log_error(f"Invalid JSON response from auth_test (GET): {e}", print_auth_test_response)
            except (IndexError, TypeError) as e:
                log_error(f"GET /rpc/auth_test returned unexpected JSON structure: {response.text}. Error: {e}")

        else:
            def print_auth_test_error():
                print(f"{RED}Response (GET): {response.text}{NC}")
            log_error(f"Auth test endpoint (GET) returned status {response.status_code}", print_auth_test_error)
    
    except requests.RequestException as e:
        log_error(f"API request (GET /rpc/auth_test) failed: {e}")
    # Ensure logs are collected even if GET fails before POST
    # The main try/finally will handle stopping the collector

    # Test POST request to /rpc/auth_test
    log_info(f"Testing auth_test endpoint with POST (logged in: {logged_in})...")
    try:
        response_post = session.post(
            f"{CADDY_BASE_URL}/rest/rpc/auth_test",
            headers={"Content-Type": "application/json"},
            json={} # Empty JSON body for POST RPC
        )
        if response_post.status_code == 200:
            log_success(f"Auth test endpoint (POST) returned status 200")
            try:
                data_post = response_post.json()
                actual_data_post = data_post[0] if isinstance(data_post, list) and len(data_post) == 1 else data_post

                if os.environ.get("DEBUG"):
                    print(f"\n{YELLOW}=== Auth Test Response (POST, {logged_in=}) ==={NC}")
                    print(f"{YELLOW}{json.dumps(actual_data_post, indent=2)}{NC}\n")

                if logged_in:
                    access_token_details_post = actual_data_post.get("access_token", {})
                    access_token_claims_post = access_token_details_post.get("claims", {})
                    user_email_in_token_post = access_token_claims_post.get("email")

                    expected_email_for_session = (ADMIN_EMAIL if "admin" in session.headers.get("User-Agent", "") else
                                                  REGULAR_EMAIL if "regular" in session.headers.get("User-Agent", "") else
                                                  RESTRICTED_EMAIL if "restricted" in session.headers.get("User-Agent", "") else None)

                    if access_token_details_post.get("present") and user_email_in_token_post == expected_email_for_session:
                        log_success(f"POST /rpc/auth_test: 'access_token.claims.email' ({user_email_in_token_post}) correctly matches logged-in user ({expected_email_for_session}).")
                    elif access_token_details_post.get("present"):
                        log_problem_reproduced(f"POST /rpc/auth_test: 'access_token.claims.email' ({user_email_in_token_post}) does not match expected user ({expected_email_for_session}) although token is present. Token claims: {access_token_claims_post}")
                    else:
                        log_problem_reproduced(f"POST /rpc/auth_test: Access token not present in response for an expected logged-in session.")
                    
                    top_level_claims_post = actual_data_post.get("claims", {})
                    log_info(f"  POST /rpc/auth_test: Top-level 'claims' (from GUC) for this session: {json.dumps(top_level_claims_post)}")
                    if top_level_claims_post.get("role") != "anon": # This is the GUC value
                        log_warning(f"  POST /rpc/auth_test: Top-level 'claims.role' (GUC) was '{top_level_claims_post.get('role')}', not 'anon' as potentially expected for SECURITY INVOKER entry point.")

                    # Verify current_db_user and current_db_role from the function's perspective
                    db_user_post = actual_data_post.get("current_db_user")
                    db_role_post = actual_data_post.get("current_db_role")
                    if db_user_post == expected_email_for_session:
                        log_success(f"  POST /rpc/auth_test: 'current_db_user' ({db_user_post}) matches expected authenticated user.")
                    else:
                        log_problem_reproduced(f"  POST /rpc/auth_test: 'current_db_user' ({db_user_post}) does not match expected authenticated user ({expected_email_for_session}).")
                    
                    if db_role_post == expected_email_for_session: # In PG, after SET ROLE, current_user is the role
                        log_success(f"  POST /rpc/auth_test: 'current_db_role' ({db_role_post}) matches expected authenticated role.")
                    else:
                        log_problem_reproduced(f"  POST /rpc/auth_test: 'current_db_role' ({db_role_post}) does not match expected authenticated role ({expected_email_for_session}).")

                elif not logged_in: # Unauthenticated
                    top_level_claims_role_post = actual_data_post.get("claims", {}).get("role")
                    db_user_unauth_post = actual_data_post.get("current_db_user")
                    db_role_unauth_post = actual_data_post.get("current_db_role")

                    if top_level_claims_role_post == "anon":
                        log_success("POST /rpc/auth_test: Top-level 'claims.role' (GUC) is 'anon' as expected for unauthenticated session.")
                    else:
                        log_warning(f"POST /rpc/auth_test: Top-level 'claims.role' (GUC) is '{top_level_claims_role_post}', expected 'anon'.")

                    if db_user_unauth_post == "anon":
                        log_success(f"  POST /rpc/auth_test: 'current_db_user' is '{db_user_unauth_post}' as expected for unauthenticated session.")
                    else:
                        log_problem_reproduced(f"  POST /rpc/auth_test: 'current_db_user' is '{db_user_unauth_post}', expected 'anon'.")

                    if db_role_unauth_post == "anon":
                        log_success(f"  POST /rpc/auth_test: 'current_db_role' is '{db_role_unauth_post}' as expected for unauthenticated session.")
                    else:
                        log_problem_reproduced(f"  POST /rpc/auth_test: 'current_db_role' is '{db_role_unauth_post}', expected 'anon'.")
            
            except json.JSONDecodeError as e:
                def print_auth_test_post_response():
                    print(f"{RED}Response text (POST): {response_post.text!r}{NC}")
                log_error(f"Invalid JSON response from auth_test (POST): {e}", print_auth_test_post_response)
            except (IndexError, TypeError) as e:
                log_error(f"POST /rpc/auth_test returned unexpected JSON structure: {response_post.text}. Error: {e}")
        else:
            def print_auth_test_post_error():
                print(f"{RED}Response (POST): {response_post.text}{NC}")
            log_error(f"Auth test endpoint (POST) returned status {response_post.status_code}", print_auth_test_post_error)
    except requests.RequestException as e:
        log_error(f"API request (POST /rpc/auth_test) failed: {e}")
    finally:
        collector.stop()
        if not log_q.empty():
            print(f"\n{BLUE}--- Collected Docker Logs for test_auth_test_endpoint ---{NC}")
            while not log_q.empty():
                try:
                    log_line = log_q.get_nowait()
                    print(log_line)
                except queue.Empty:
                    break
            print(f"{BLUE}--- End of Docker Logs ---{NC}\n")

def test_auth_status_post(session: Session, expected_auth: bool) -> None:
    """Test auth status using POST"""
    log_info(f"Testing auth status with POST (expected authenticated: {expected_auth})...")
        
    try:
        debug_info(f"Session cookies before POST request to auth_status: {session.cookies}")
        response = session.post( # Use POST
            f"{CADDY_BASE_URL}/rest/rpc/auth_status",
            headers={"Content-Type": "application/json"},
            json={} # Send empty JSON body for POST RPC
        )
        
        debug_info(f"Auth status (POST) response code: {response.status_code}")
        debug_info(f"Auth status (POST) response headers: {dict(response.headers)}")
        debug_info(f"Auth status (POST) raw response: {response.text}")
        
        try:
            data = response.json()
            # PostgREST RPCs that return a single row might wrap it in an array
            actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
            debug_info(f"Auth status (POST) parsed response: {json.dumps(actual_data, indent=2)}")
                
            if actual_data.get("is_authenticated") == expected_auth:
                log_success(f"Auth status (POST) returned expected authentication state: {expected_auth}")
            else:
                def print_auth_status_details():
                    print(f"{RED}Response (POST): {json.dumps(actual_data, indent=2)}{NC}")
                    print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/auth_status (POST){NC}")
                    print(f"{RED}Expected is_authenticated: {expected_auth}{NC}")
                
                log_error(f"Auth status (POST) did not return expected authentication state.", print_auth_status_details)
        except json.JSONDecodeError as e:
            def print_auth_status_response_details():
                print(f"{RED}Response text (POST): {response.text!r}{NC}")
                print(f"{RED}Response status (POST): {response.status_code}{NC}")
                print(f"{RED}Response headers (POST): {dict(response.headers)}{NC}")
            
            log_error(f"Invalid JSON response from auth_status (POST): {e}", print_auth_status_response_details)
    
    except requests.RequestException as e:
        log_error(f"API request (POST /rpc/auth_status) failed: {e}")

def main() -> None:
    """Main test sequence"""
    print(f"\n{BLUE}=== Starting Authentication System Tests ==={NC}\n")
    print(f"{BLUE}Using API URL: {CADDY_BASE_URL}{NC}")
    print(f"{BLUE}Using DB: {DB_HOST}:{DB_PORT}/{DB_NAME}{NC}")
    
    # Initialize test environment
    initialize_test_environment()
    
    # Create a session for unauthenticated tests
    unauthenticated_session = requests.Session()
    
    # Test auth_test endpoint before login
    print(f"\n{BLUE}=== Test 0: Auth Test Endpoint (Before Login) ==={NC}")
    test_auth_test_endpoint(unauthenticated_session, logged_in=False)
    
    # Create a session for admin user
    admin_session = requests.Session()
    
    # Test 1: Admin user API login and access
    print(f"\n{BLUE}=== Test 1: Admin User API Login and Access ==={NC}")
    admin_session.headers.update({"User-Agent": "test_user_admin"}) # For test_auth_test_endpoint user check
    admin_id = test_api_login(admin_session, ADMIN_EMAIL, ADMIN_PASSWORD, "admin_user")
    test_api_access(admin_session, ADMIN_EMAIL, "/rest/region?limit=10", 200)
    test_auth_status(admin_session, True)
    test_auth_status_post(admin_session, True) # Add POST test
    
    # Test auth_test endpoint after login
    print(f"\n{BLUE}=== Test 1.1: Auth Test Endpoint (After Login) ==={NC}")
    test_auth_test_endpoint(admin_session, logged_in=True) # Will test GET and POST
    
    # Test 2: Admin user direct database access
    print(f"\n{BLUE}=== Test 2: Admin User Direct Database Access ==={NC}")
    test_db_access(ADMIN_EMAIL, ADMIN_PASSWORD, "SELECT statbus_role FROM auth.user WHERE email = current_user;", "admin_user")
    test_db_access(ADMIN_EMAIL, ADMIN_PASSWORD, "SELECT COUNT(*) FROM auth.user;", "[0-9]+")
    test_db_access(ADMIN_EMAIL, ADMIN_PASSWORD, "SELECT auth.sub()::text;", "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") # Check auth.sub() returns a UUID
    
    # Create a session for regular user
    regular_session = requests.Session()
    
    # Test 3: Regular user API login and access
    print(f"\n{BLUE}=== Test 3: Regular User API Login and Access ==={NC}")
    test_api_logout(admin_session) # This clears admin_session's User-Agent too if headers are cleared by session
    admin_session.headers.clear() # Explicitly clear headers
    
    regular_session.headers.update({"User-Agent": "test_user_regular"})
    regular_id = test_api_login(regular_session, REGULAR_EMAIL, REGULAR_PASSWORD, "regular_user")
    test_api_access(regular_session, REGULAR_EMAIL, "/rest/region?limit=10", 200)
    test_auth_status(regular_session, True)
    test_auth_status_post(regular_session, True) # Add POST test
    
    # Test 4: Regular user direct database access
    print(f"\n{BLUE}=== Test 4: Regular User Direct Database Access ==={NC}")
    test_db_access(REGULAR_EMAIL, REGULAR_PASSWORD, "SELECT statbus_role FROM auth.user WHERE email = current_user;", "regular_user")
    test_db_access(REGULAR_EMAIL, REGULAR_PASSWORD, "SELECT COUNT(*) FROM public.region;", "[0-9]+")
    test_db_access(REGULAR_EMAIL, REGULAR_PASSWORD, "SELECT auth.sub()::text;", "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") # Check auth.sub() returns a UUID
    
    # Create a session for restricted user
    restricted_session = requests.Session()
    
    # Test 5: Restricted user API login and access
    print(f"\n{BLUE}=== Test 5: Restricted User API Login and Access ==={NC}")
    test_api_logout(regular_session)
    regular_session.headers.clear()

    restricted_session.headers.update({"User-Agent": "test_user_restricted"})
    restricted_id = test_api_login(restricted_session, RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "restricted_user")
    test_api_access(restricted_session, RESTRICTED_EMAIL, "/rest/region?limit=10", 200)
    test_auth_status(restricted_session, True)
    test_auth_status_post(restricted_session, True) # Add POST test
    
    # Test 6: Restricted user direct database access
    print(f"\n{BLUE}=== Test 6: Restricted User Direct Database Access ==={NC}")
    test_db_access(RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "SELECT statbus_role FROM auth.user WHERE email = current_user;", "restricted_user")
    test_db_access(RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "SELECT COUNT(*) FROM public.region;", "[0-9]+")
    test_db_access(RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "SELECT auth.sub()::text;", "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") # Check auth.sub() returns a UUID
    
    # Create a new session for token refresh test
    refresh_session = requests.Session()
    
    # Test 7: Token refresh
    print(f"\n{BLUE}=== Test 7: Token Refresh ==={NC}")
    test_api_logout(restricted_session)
    restricted_session.headers.clear()

    refresh_session.headers.update({"User-Agent": "test_user_admin_for_refresh"}) # For login within test_token_refresh
    test_token_refresh(refresh_session, ADMIN_EMAIL, ADMIN_PASSWORD)
    
    # Test 8: Logout and verify authentication state
    print(f"\n{BLUE}=== Test 8: Logout and Verify Authentication State ==={NC}")
    test_api_logout(refresh_session) # refresh_session should be logged out by test_token_refresh already
    refresh_session.headers.clear()
    test_auth_status(refresh_session, False) 
    test_auth_status_post(refresh_session, False) # Add POST test
    
    # Test 9: Failed login with incorrect password
    print(f"\n{BLUE}=== Test 9: Failed Login with Incorrect Password ==={NC}")
    log_info("Testing login with incorrect password...")
    failed_login_session = requests.Session()
    try:
        response = failed_login_session.post(
            f"{CADDY_BASE_URL}/rest/rpc/login",
            json={"email": ADMIN_EMAIL, "password": "WrongPassword"},
            headers={"Content-Type": "application/json"}
        )
        
        data = response.json()
        if data.get("uid") is None and data.get("access_jwt") is None:
            log_success("Login correctly failed with incorrect password")
        else:
            def print_unexpected_login_success():
                print(f"{RED}Response: {response.text}{NC}")
                print(f"{RED}API endpoint: {CADDY_BASE_URL}/rest/rpc/login{NC}")
            
            log_error("Login unexpectedly succeeded with incorrect password.", print_unexpected_login_success)
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
    
    # Test 10: Failed database access with incorrect password
    print(f"\n{BLUE}=== Test 10: Failed Database Access with Incorrect Password ==={NC}")
    log_info("Testing database access with incorrect password...")
    result = run_psql_command("SELECT 1;", ADMIN_EMAIL, "WrongPassword")
    
    if "password authentication failed" in result:
        log_success("Database access correctly failed with incorrect password")
    else:
        def print_unexpected_db_access():
            print(f"{RED}Result: {result}{NC}")
            print(f"{RED}Connection: {ADMIN_EMAIL}@{DB_HOST}:{DB_PORT}/{DB_NAME}{NC}")
        
        log_error("Database access unexpectedly succeeded with incorrect password.", print_unexpected_db_access)
    
    # Test 11: API access with Bearer token
    print(f"\n{BLUE}=== Test 11: API Access with Bearer Token ==={NC}")
    test_bearer_token_auth(ADMIN_EMAIL, ADMIN_PASSWORD)
    
    # CORS tests removed as they're no longer needed with the simplified architecture

    # Test 12: API Key Management
    print(f"\n{BLUE}=== Test 12: API Key Management ==={NC}")
    # Use regular user session for API key tests
    # Ensure the regular user is logged in before running this test
    test_api_login(regular_session, REGULAR_EMAIL, REGULAR_PASSWORD, "regular_user")
    test_api_key_management(regular_session, REGULAR_EMAIL, REGULAR_PASSWORD)

    # Test 13: Role Switching with SET LOCAL ROLE
    print(f"\n{BLUE}=== Test 13: Role Switching with SET LOCAL ROLE ==={NC}")
    log_info("Testing role switching with SET LOCAL ROLE...")
    
    # Test with admin user
    admin_role_test = """
    BEGIN;
    -- Verify we can see all users as admin
    SET LOCAL ROLE "%s";
    SELECT COUNT(*) FROM auth.user;
    -- Try to access a sensitive function
    SELECT COUNT(*) FROM auth.refresh_session;
    END;
    """ % ADMIN_EMAIL
    
    admin_result = run_psql_command(admin_role_test, ADMIN_EMAIL, ADMIN_PASSWORD)
    if "ERROR" not in admin_result:
        log_success("Admin role switching test passed - can access sensitive data")
        debug_info(f"Admin role test result: {admin_result}")
    else:
        log_error(f"Admin role switching test failed: {admin_result}")
    
    # Test with regular user
    regular_role_test = """
    BEGIN;
    -- Switch to regular user role
    SET LOCAL ROLE "%s";
    -- Should be able to see public data
    SELECT COUNT(*) FROM public.region;
    -- Try to access sensitive data (should fail or be limited by RLS)
    SELECT COUNT(*) FROM auth.user WHERE email = current_user;
    END;
    """ % REGULAR_EMAIL
    
    regular_result = run_psql_command(regular_role_test, REGULAR_EMAIL, REGULAR_PASSWORD)
    if "ERROR" not in regular_result or "permission denied" in regular_result:
        log_success("Regular user role switching test passed - limited access as expected")
        debug_info(f"Regular user role test result: {regular_result}")
    else:
        log_warning(f"Regular user role test had unexpected result: {regular_result}")
    
    # Test with restricted user
    restricted_role_test = """
    BEGIN;
    -- Switch to restricted user role
    SET LOCAL ROLE "%s";
    -- Should be able to see public data
    SELECT COUNT(*) FROM public.region;
    -- Try to access sensitive data (should fail)
    BEGIN;
        SELECT COUNT(*) FROM auth.user;
        RAISE EXCEPTION 'Should not be able to access auth.user';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'Correctly denied access to auth.user';
    END;
    END;
    """ % RESTRICTED_EMAIL
    
    restricted_result = run_psql_command(restricted_role_test, RESTRICTED_EMAIL, RESTRICTED_PASSWORD)
    if "ERROR" not in restricted_result or "permission denied" in restricted_result:
        log_success("Restricted user role switching test passed - properly limited access")
        debug_info(f"Restricted user role test result: {restricted_result}")
    else:
        log_warning(f"Restricted user role test had unexpected result: {restricted_result}")
    
    # Test 15: Password Change and Session Invalidation
    print(f"\n{BLUE}=== Test 15: Password Change and Session Invalidation ==={NC}")
    # Need admin session for admin part, and a fresh session for the user being changed
    password_change_user_session = requests.Session()
    test_password_change(admin_session, password_change_user_session, RESTRICTED_EMAIL, RESTRICTED_PASSWORD)

    # Print summary of test results
    if PROBLEM_REPRODUCED_FLAG:
        log_info(f"\n{RED}=== Some Authentication Problems Were Reproduced ==={NC}\n")
        sys.exit(1)
    else:
        print(f"\n{GREEN}=== All Authentication Tests Completed Successfully ==={NC}\n")
        sys.exit(0)


def cleanup_test_user_sessions() -> None:
    """Clean up refresh sessions for test users from the database."""
    log_info("Cleaning up test user sessions...")
    test_user_emails = [ADMIN_EMAIL, REGULAR_EMAIL, RESTRICTED_EMAIL]
    # Convert list of emails to a SQL string like "'email1', 'email2', 'email3'"
    email_list_sql = ", ".join([f"'{email}'" for email in test_user_emails])
    
    query = f"""
    DELETE FROM auth.refresh_session
    WHERE user_id IN (
        SELECT id FROM auth.user WHERE email IN ({email_list_sql})
    );
    """
    
    # Use admin credentials to perform the cleanup
    result = run_psql_command(query, user=ADMIN_EMAIL, password=ADMIN_PASSWORD)
    
    # Check for errors in the result. psql -t with DELETE usually returns no output on success.
    # Errors typically include "ERROR", "FATAL", or "permission denied".
    if "ERROR" in result.upper() or "FAILED" in result.upper() or "FATAL" in result.upper() or "PERMISSION DENIED" in result.upper():
        log_warning(f"Failed to cleanup test user sessions. Result: {result}")
    else:
        log_success("Test user sessions cleaned up successfully.")
        debug_info(f"Cleanup result: {result if result else 'No output from DELETE, assumed OK.'}")

if __name__ == "__main__":
    atexit.register(cleanup_test_user_sessions)
    main()
