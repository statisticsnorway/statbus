#!/usr/bin/env python3
"""
Test script for authentication in standalone mode
Tests both API access and direct database access with the same credentials
Run with `./test/auth_for_standalone.sh` that uses venv.
"""

import os
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
        debug_info(f"Sending login request to {CADDY_BASE_URL}/postgrest/rpc/login")
        debug_info(f"Request payload: {{'email': '{email}', 'password': '********'}}")
        
        response = session.post(
            f"{CADDY_BASE_URL}/postgrest/rpc/login",
            json={"email": email, "password": password},
            headers={"Content-Type": "application/json"}
        )
        
        debug_info(f"Response status code: {response.status_code}")
        debug_info(f"Response headers: {dict(response.headers)}")
        
        # Check if response is not successful
        if response.status_code != 200:
            def print_response_debug_info():
                print(f"Response body: {response.text}")
                print(f"API endpoint: {CADDY_BASE_URL}/postgrest/rpc/login")
            
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
                    print(f"API endpoint: {CADDY_BASE_URL}/postgrest/rpc/login")
                
                log_error(f"API login failed for {email}. Empty response from server.", print_endpoint_info)
                return None
                
            data = response.json()
            debug_info(f"Login response: {json.dumps(data, indent=2)}")
        except json.JSONDecodeError as e:
            def print_response_details():
                print(f"Response text: {response.text!r}")  # Use repr to show whitespace/control chars
                print(f"Response headers: {dict(response.headers)}")
                print(f"API endpoint: {CADDY_BASE_URL}/postgrest/rpc/login")
            
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
            return data.get("user_id")
        else:
            def print_login_failure_details():
                print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
                print(f"{RED}API endpoint: {CADDY_BASE_URL}/postgrest/rpc/login{NC}")
            
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
            f"{CADDY_BASE_URL}/postgrest/rpc/logout",
            headers={"Content-Type": "application/json"}
        )
        
        # Check if logout was successful
        data = response.json()
        if data.get("success") is True:
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
            print(f"{RED}API endpoint: {CADDY_BASE_URL}/postgrest/rpc/logout{NC}")
    
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
            f"{CADDY_BASE_URL}/postgrest/rpc/refresh",
            headers={"Content-Type": "application/json"}
        )
        
        # Check if refresh was successful
        data = response.json()
        if "access_jwt" in data:
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
            print(f"{RED}API endpoint: {CADDY_BASE_URL}/postgrest/rpc/refresh{NC}")
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")
    except json.JSONDecodeError:
        log_error(f"Invalid JSON response from server")
        print(f"{RED}Response text: {response.text}{NC}")

def test_auth_status(session: Session, expected_auth: bool) -> None:
    """Test auth status"""
    log_info(f"Testing auth status (expected authenticated: {expected_auth})...")
    
    debug_info(f"Session cookies: {session.cookies}")
    
    # Make auth status request
    try:
        response = session.get(
            f"{CADDY_BASE_URL}/postgrest/rpc/auth_status",
            headers={"Content-Type": "application/json"}
        )
        
        debug_info(f"Auth status response code: {response.status_code}")
        debug_info(f"Auth status response headers: {dict(response.headers)}")
        debug_info(f"Auth status raw response: {response.text}")
        
        # Check if auth status matches expectation
        try:
            data = response.json()
            debug_info(f"Auth status parsed response: {json.dumps(data, indent=2)}")
            
            if data.get("isAuthenticated") == expected_auth:
                log_success(f"Auth status returned expected authentication state: {expected_auth}")
            else:
                def print_auth_status_details():
                    print(f"{RED}Response: {json.dumps(data, indent=2)}{NC}")
                    print(f"{RED}API endpoint: {CADDY_BASE_URL}/postgrest/rpc/auth_status{NC}")
                    print(f"{RED}Expected isAuthenticated: {expected_auth}{NC}")
                
                log_error(f"Auth status did not return expected authentication state.", print_auth_status_details)
        except json.JSONDecodeError as e:
            def print_auth_status_response_details():
                print(f"{RED}Response text: {response.text!r}{NC}")
                print(f"{RED}Response status: {response.status_code}{NC}")
                print(f"{RED}Response headers: {dict(response.headers)}{NC}")
            
            log_error(f"Invalid JSON response from auth_status: {e}", print_auth_status_response_details)
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")

# CORS test functions removed as they're no longer needed with the simplified architecture

def test_auth_test_endpoint(session: Session, logged_in: bool = False) -> None:
    """Test the auth_test endpoint to get detailed debug information"""
    log_info(f"Testing auth_test endpoint (logged in: {logged_in})...")
    
    # Make auth_test request
    try:
        response = session.get(
            f"{CADDY_BASE_URL}/postgrest/rpc/auth_test",
            headers={"Content-Type": "application/json"}
        )
        
        # Check if request was successful
        if response.status_code == 200:
            log_success(f"Auth test endpoint returned status 200")
            
            # Parse and print the response if in debug mode
            try:
                data = response.json()
                if os.environ.get("DEBUG"):
                    print(f"\n{YELLOW}=== Auth Test Response ({logged_in=}) ==={NC}")
                    print(f"{YELLOW}{json.dumps(data, indent=2)}{NC}\n")
            except json.JSONDecodeError as e:
                def print_auth_test_response():
                    print(f"{RED}Response text: {response.text!r}{NC}")
                
                log_error(f"Invalid JSON response from auth_test: {e}", print_auth_test_response)
        else:
            def print_auth_test_error():
                print(f"{RED}Response: {response.text}{NC}")
            
            log_error(f"Auth test endpoint returned status {response.status_code}", print_auth_test_error)
    
    except requests.RequestException as e:
        log_error(f"API request failed: {e}")

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
    admin_id = test_api_login(admin_session, ADMIN_EMAIL, ADMIN_PASSWORD, "admin_user")
    test_api_access(admin_session, ADMIN_EMAIL, "/postgrest/region?limit=10", 200)
    test_auth_status(admin_session, True)
    
    # Test auth_test endpoint after login
    print(f"\n{BLUE}=== Test 1.1: Auth Test Endpoint (After Login) ==={NC}")
    test_auth_test_endpoint(admin_session, logged_in=True)
    
    # Test 2: Admin user direct database access
    print(f"\n{BLUE}=== Test 2: Admin User Direct Database Access ==={NC}")
    test_db_access(ADMIN_EMAIL, ADMIN_PASSWORD, "SELECT statbus_role FROM auth.user WHERE email = current_user;", "admin_user")
    test_db_access(ADMIN_EMAIL, ADMIN_PASSWORD, "SELECT COUNT(*) FROM auth.user;", "[0-9]+")
    
    # Create a session for regular user
    regular_session = requests.Session()
    
    # Test 3: Regular user API login and access
    print(f"\n{BLUE}=== Test 3: Regular User API Login and Access ==={NC}")
    test_api_logout(admin_session)
    regular_id = test_api_login(regular_session, REGULAR_EMAIL, REGULAR_PASSWORD, "regular_user")
    test_api_access(regular_session, REGULAR_EMAIL, "/postgrest/region?limit=10", 200)
    test_auth_status(regular_session, True)
    
    # Test 4: Regular user direct database access
    print(f"\n{BLUE}=== Test 4: Regular User Direct Database Access ==={NC}")
    test_db_access(REGULAR_EMAIL, REGULAR_PASSWORD, "SELECT statbus_role FROM auth.user WHERE email = current_user;", "regular_user")
    test_db_access(REGULAR_EMAIL, REGULAR_PASSWORD, "SELECT COUNT(*) FROM public.region;", "[0-9]+")
    
    # Create a session for restricted user
    restricted_session = requests.Session()
    
    # Test 5: Restricted user API login and access
    print(f"\n{BLUE}=== Test 5: Restricted User API Login and Access ==={NC}")
    test_api_logout(regular_session)
    restricted_id = test_api_login(restricted_session, RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "restricted_user")
    test_api_access(restricted_session, RESTRICTED_EMAIL, "/postgrest/region?limit=10", 200)
    test_auth_status(restricted_session, True)
    
    # Test 6: Restricted user direct database access
    print(f"\n{BLUE}=== Test 6: Restricted User Direct Database Access ==={NC}")
    test_db_access(RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "SELECT statbus_role FROM auth.user WHERE email = current_user;", "restricted_user")
    test_db_access(RESTRICTED_EMAIL, RESTRICTED_PASSWORD, "SELECT COUNT(*) FROM public.region;", "[0-9]+")
    
    # Create a new session for token refresh test
    refresh_session = requests.Session()
    
    # Test 7: Token refresh
    print(f"\n{BLUE}=== Test 7: Token Refresh ==={NC}")
    test_api_logout(restricted_session)
    test_token_refresh(refresh_session, ADMIN_EMAIL, ADMIN_PASSWORD)
    
    # Test 8: Logout and verify authentication state
    print(f"\n{BLUE}=== Test 8: Logout and Verify Authentication State ==={NC}")
    test_api_logout(refresh_session)
    test_auth_status(refresh_session, False)
    
    # Test 9: Failed login with incorrect password
    print(f"\n{BLUE}=== Test 9: Failed Login with Incorrect Password ==={NC}")
    log_info("Testing login with incorrect password...")
    failed_login_session = requests.Session()
    try:
        response = failed_login_session.post(
            f"{CADDY_BASE_URL}/postgrest/rpc/login",
            json={"email": ADMIN_EMAIL, "password": "WrongPassword"},
            headers={"Content-Type": "application/json"}
        )
        
        if not response.text or response.text.strip() == "null":
            log_success("Login correctly failed with incorrect password")
        else:
            def print_unexpected_login_success():
                print(f"{RED}Response: {response.text}{NC}")
                print(f"{RED}API endpoint: {CADDY_BASE_URL}/postgrest/rpc/login{NC}")
            
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
    
    # CORS tests removed as they're no longer needed with the simplified architecture
    
    # Print summary of test results
    print(f"\n{GREEN}=== All Authentication Tests Completed Successfully ==={NC}\n")

if __name__ == "__main__":
    main()
