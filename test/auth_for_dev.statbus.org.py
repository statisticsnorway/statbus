#!/usr/bin/env python3
"""
Test script for authentication against https://dev.statbus.org/
Attempts to reproduce issues outlined in auth-problem.md.
Run with `./test/auth_for_dev.statbus.org.sh`.
"""

import os
import sys
import json
import requests
from requests.sessions import Session
from typing import Optional, Dict, Any
import subprocess
import threading
import time
import queue
import yaml
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

# Configuration
DEV_API_URL = "https://dev.statbus.org" # Target the dev environment
USER_EMAIL = None # Will be fetched
USER_PASSWORD = None # Will be fetched

# Global flag to track if any problem was reproduced
PROBLEM_REPRODUCED_FLAG = False

def log_problem_reproduced(message: str):
    global PROBLEM_REPRODUCED_FLAG
    PROBLEM_REPRODUCED_FLAG = True
    print(f"{RED}PROBLEM REPRODUCED: {message}{NC}")

def log_info(message: str):
    print(f"{BLUE}{message}{NC}")

def log_success_condition(message: str): # Indicates a condition for reproduction was met
    print(f"{GREEN}✓ {message}{NC}")

def log_failure_condition(message: str): # Indicates a condition for reproduction was NOT met
    print(f"{YELLOW}✗ {message}{NC}")

def log_error_critical(message: str): # For critical script errors, not test failures
    print(f"{RED}CRITICAL SCRIPT ERROR: {message}{NC}")
    sys.exit(1)

def debug_info(message: str):
    if os.environ.get("DEBUG"):
        print(f"{YELLOW}DEBUG: {message}{NC}")

class RemoteLogCollector:
    def __init__(self, ssh_target: str, remote_command_dir: str, services: list[str], log_queue: queue.Queue):
        self.ssh_target = ssh_target
        self.remote_command_dir = remote_command_dir
        self.services = services
        self.log_queue = log_queue
        self.process: Optional[subprocess.Popen] = None
        self.stdout_thread: Optional[threading.Thread] = None
        self.stderr_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    def _reader_thread_target(self, pipe, stream_name):
        try:
            for line in iter(pipe.readline, ''):
                if self._stop_event.is_set():
                    break
                self.log_queue.put(f"[{self.ssh_target} {stream_name}] {line.strip()}")
            pipe.close()
        except Exception as e:
            self.log_queue.put(f"[{self.ssh_target} {stream_name} ERROR] Exception in reader thread: {e}")


    def start(self):
        self._stop_event.clear()
        # Using --since 1s to get very recent history plus new logs.
        # Adjust if more history is needed or if clock sync is an issue.
        command_str = f"cd {self.remote_command_dir} && docker compose logs --follow --since 1s {' '.join(self.services)}"
        ssh_command = ['ssh', self.ssh_target, command_str]
        
        log_info(f"Starting remote log collection: {' '.join(ssh_command)}")
        try:
            self.process = subprocess.Popen(
                ssh_command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1, # Line-buffered
                errors='replace' 
            )
        except FileNotFoundError:
            self.log_queue.put(f"[LOCAL ERROR] ssh command not found. Ensure ssh client is installed and in PATH.")
            return
        except Exception as e:
            self.log_queue.put(f"[LOCAL ERROR] Failed to start ssh process: {e}")
            return

        if self.process.stdout:
            self.stdout_thread = threading.Thread(target=self._reader_thread_target, args=(self.process.stdout, "stdout"))
            self.stdout_thread.daemon = True
            self.stdout_thread.start()

        if self.process.stderr:
            self.stderr_thread = threading.Thread(target=self._reader_thread_target, args=(self.process.stderr, "stderr"))
            self.stderr_thread.daemon = True
            self.stderr_thread.start()
        
        # Give SSH a moment to connect and docker logs to start streaming
        time.sleep(2) # Adjust if needed

    def stop(self):
        log_info(f"Stopping remote log collection for {self.ssh_target}...")
        self._stop_event.set() # Signal reader threads to stop

        if self.process:
            if self.process.poll() is None: # If process is still running
                try:
                    self.process.terminate() # Send SIGTERM
                    try:
                        self.process.wait(timeout=5) # Wait for termination
                    except subprocess.TimeoutExpired:
                        log_warning(f"Remote log collector process for {self.ssh_target} did not terminate gracefully, killing.")
                        self.process.kill() # Send SIGKILL
                        try:
                            self.process.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            log_error_critical(f"Failed to kill remote log collector process for {self.ssh_target}.")
                except Exception as e:
                    log_warning(f"Error terminating remote log collector process: {e}")
            self.process = None

        if self.stdout_thread and self.stdout_thread.is_alive():
            self.stdout_thread.join(timeout=2)
        if self.stderr_thread and self.stderr_thread.is_alive():
            self.stderr_thread.join(timeout=2)
        log_info("Remote log collection stopped.")

def login_user(session: Session) -> Optional[Dict[str, str]]:
    """Logs in the user and returns cookies if successful."""
    log_info(f"Attempting login for {USER_EMAIL} at {DEV_API_URL}...")
    try:
        response = session.post(
            f"{DEV_API_URL}/rest/rpc/login",
            json={"email": USER_EMAIL, "password": USER_PASSWORD},
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        debug_info(f"Login response status: {response.status_code}")
        debug_info(f"Login response headers: {dict(response.headers)}")
        debug_info(f"Login response cookies: {response.cookies.get_dict()}")
        
        if response.status_code == 200:
            try:
                data = response.json()
                debug_info(f"Login response body: {json.dumps(data, indent=2)}")
                if data.get("is_authenticated"):
                    log_info(f"Login successful for {USER_EMAIL}.")
                    # Extract statbus (access) and statbus-refresh cookies
                    access_token = session.cookies.get("statbus")
                    refresh_token = session.cookies.get("statbus-refresh")
                    if not access_token:
                         log_failure_condition("Access token (statbus cookie) not found after login.")
                    if not refresh_token:
                         log_failure_condition("Refresh token (statbus-refresh cookie) not found after login.")
                    return {"access": access_token, "refresh": refresh_token, "full_session_cookies": session.cookies.get_dict()}
                else:
                    log_failure_condition(f"Login failed: is_authenticated is false. Response: {data}")
                    return None
            except json.JSONDecodeError:
                log_failure_condition(f"Login failed: Could not decode JSON response. Body: {response.text}")
                return None
        else:
            log_failure_condition(f"Login request failed with status {response.status_code}. Body: {response.text}")
            return None
    except requests.RequestException as e:
        log_error_critical(f"Login request exception: {e}")
        return None

def test_dev_auth_status_malfunction(session: Session, access_token_value: Optional[str]):
    """
    Tests Problem 1 from auth-problem.md: Server-side rpc/auth_status malfunction.
    Expected problem: returns data: null or is_authenticated: false for a valid token.
    """
    log_info("\nTesting Problem 1: /rpc/auth_status malfunction...")
    if not access_token_value:
        log_failure_condition("Skipping auth_status test: No access token provided (login likely failed).")
        return

    try:
        # The /rpc/auth_status endpoint primarily relies on the JWT being passed by PostgREST
        # from the cookie, which the session object handles.
        # Forcing Authorization header might also work if PostgREST is configured for it.
        # Let's rely on the session cookie first, as that's closer to browser behavior.
        response = session.get(f"{DEV_API_URL}/rest/rpc/auth_status", timeout=10)
        
        debug_info(f"auth_status response status: {response.status_code}")
        debug_info(f"auth_status response headers: {dict(response.headers)}")
        debug_info(f"auth_status response body: {response.text}")

        if response.status_code == 200:
            if not response.text or response.text.lower() == "null" or response.text == "[]":
                log_problem_reproduced(f"/rpc/auth_status returned an empty or null body: '{response.text}'")
                return

            try:
                data = response.json()
                # PostgREST often wraps single RPC results in an array.
                actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data

                if actual_data is None:
                    log_problem_reproduced("/rpc/auth_status returned JSON null in the data part.")
                elif not actual_data.get("is_authenticated"):
                    log_problem_reproduced(f"/rpc/auth_status returned is_authenticated:false. Full response: {actual_data}")
                else:
                    log_failure_condition(f"/rpc/auth_status seems OK: is_authenticated is true. Response: {actual_data}")
            except json.JSONDecodeError:
                log_problem_reproduced(f"/rpc/auth_status returned non-JSON response: {response.text}")
            except (IndexError, TypeError):
                 log_problem_reproduced(f"/rpc/auth_status returned unexpected JSON structure: {response.text}")
        else:
            log_failure_condition(f"/rpc/auth_status call failed with status {response.status_code}. Body: {response.text}")

    except requests.RequestException as e:
        log_error_critical(f"auth_status request exception: {e}")

def test_dev_refresh_malfunction(session: Session, initial_refresh_token: Optional[str]):
    """
    Tests Problem 2 from auth-problem.md: Server-side rpc/refresh malfunction.
    Expected problem: HTTP 200 OK, but no Set-Cookie headers and/or empty body.
    """
    log_info("\nTesting Problem 2: /rpc/refresh malfunction (missing Set-Cookie / empty body)...")
    if not initial_refresh_token:
        log_failure_condition("Skipping refresh malfunction test: No initial refresh token (login likely failed or cookie missing).")
        return

    # Session should contain the statbus-refresh cookie from login.
    # This test will now specifically simulate the middleware scenario:
    # A new session is created, and only the refresh token is added to its cookies.
    
    log_info("Simulating middleware refresh: calling /rpc/refresh with ONLY the refresh token cookie.")
    
    # Create a new session for this specific test to isolate cookies
    middleware_sim_session = requests.Session()
    if initial_refresh_token:
        # Manually set only the refresh token cookie
        middleware_sim_session.cookies.set("statbus-refresh", initial_refresh_token, domain=DEV_API_URL.split("//")[-1].split("/")[0], path="/")
        debug_info(f"Cookies for middleware-simulated refresh attempt: {middleware_sim_session.cookies.get_dict()}")
    else:
        log_failure_condition("Cannot simulate middleware refresh: initial_refresh_token is missing.")
        return # Cannot proceed with this specific test

    try:
        response = middleware_sim_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10) # Empty JSON payload
        
        debug_info(f"Refresh response status (middleware simulation): {response.status_code}")
        debug_info(f"Refresh response headers: {dict(response.headers)}")
        debug_info(f"Refresh response body: {response.text}")

        reproduced_this_test = False
        if response.status_code == 200:
            # Check for missing Set-Cookie headers
            set_cookie_header = response.headers.get("Set-Cookie")
            new_statbus_cookie = response.cookies.get("statbus")
            new_refresh_cookie = response.cookies.get("statbus-refresh")

            if not set_cookie_header and not new_statbus_cookie and not new_refresh_cookie:
                log_problem_reproduced("/rpc/refresh returned 200 OK but no Set-Cookie headers were found.")
                reproduced_this_test = True
            elif not new_statbus_cookie or not new_refresh_cookie:
                log_problem_reproduced(f"/rpc/refresh returned 200 OK but one or more auth cookies are missing from Set-Cookie. Statbus: {new_statbus_cookie is not None}, Statbus-Refresh: {new_refresh_cookie is not None}")
                reproduced_this_test = True
            else:
                 log_failure_condition("/rpc/refresh returned Set-Cookie headers as expected.")
                 debug_info(f"Set-Cookie from headers: {set_cookie_header}")
                 debug_info(f"Parsed cookies by requests: statbus='{new_statbus_cookie}', statbus-refresh='{new_refresh_cookie}'")


            # Check for empty response body
            if not response.text.strip():
                log_problem_reproduced("/rpc/refresh returned 200 OK but with an empty response body.")
                reproduced_this_test = True
            else:
                try:
                    data = response.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    if not actual_data.get("is_authenticated"):
                        log_problem_reproduced(f"/rpc/refresh returned 200 OK but with is_authenticated:false. Body: {actual_data}")
                        reproduced_this_test = True
                    else:
                        log_failure_condition("/rpc/refresh returned 200 OK with a non-empty body and is_authenticated:true as expected.")
                        debug_info(f"Refresh response JSON: {json.dumps(actual_data, indent=2)}")
                except json.JSONDecodeError:
                    log_problem_reproduced(f"/rpc/refresh returned 200 OK but with a non-JSON body: {response.text}")
                    reproduced_this_test = True
            
            if not reproduced_this_test:
                log_failure_condition("Problem 2 (refresh malfunction) not reproduced. Refresh seems to work as expected.")

        else:
            log_failure_condition(f"/rpc/refresh call failed with status {response.status_code}, expected 200 OK for this test. Body: {response.text}")
            # This might indicate Problem 3 instead, or a different issue.

    except requests.RequestException as e:
        log_error_critical(f"Refresh request exception: {e}")

def test_dev_client_refresh_failure(session: Session, initial_refresh_token: Optional[str], initial_access_token: Optional[str]):
    """
    Tests Problem 3 from auth-problem.md: Client-side rpc/refresh failure (returns 401),
    and variants with missing/incorrect cookies.
    
    Args:
        session: The requests.Session object, typically after a successful login (for the first scenario).
        initial_refresh_token: The refresh token string from a successful login.
        initial_access_token: The access token string from a successful login (used for variant tests).
    """
    log_info("\nTesting Problem 3: Client-side /rpc/refresh failure (401 response with valid refresh cookie)...")
    if not initial_refresh_token:
        log_failure_condition("Skipping main client refresh failure test: No initial refresh token provided.")
        # Fall through to other variants that don't strictly need a pre-existing valid refresh token in the session
    else:
        # This part tests the scenario where a client *has* a valid refresh token and attempts to refresh.
        log_info("Attempting direct call to /rpc/refresh (simulating client-side refresh attempt with valid refresh cookie)...")
        debug_info(f"Cookies before client refresh attempt (valid): {session.cookies.get_dict()}")
        try:
            response = session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10) # Empty JSON payload
            
            debug_info(f"Client refresh attempt response status (valid): {response.status_code}")
            debug_info(f"Client refresh attempt response body: {response.text}")

            if response.status_code == 401:
                log_problem_reproduced(f"/rpc/refresh (client-side simulation) returned 401 Unauthorized.")
            elif response.status_code == 200:
                # If it's 200, check if it actually worked or if it's Problem 2
                set_cookie_header = response.headers.get("Set-Cookie")
                try:
                    data = response.json()
                    # Handle both direct object and array-wrapped object
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    
                    if not set_cookie_header or not response.text.strip() or not actual_data.get("is_authenticated"):
                        log_failure_condition(f"/rpc/refresh (client-side simulation) returned 200 OK, but might exhibit Problem 2 symptoms (missing cookies/body). This test is for 401.")
                        debug_info("This scenario might mean Problem 3 is NOT reproduced, but Problem 2 IS.")
                    else:
                        log_failure_condition(f"/rpc/refresh (client-side simulation) returned 200 OK and seems to have worked. Problem 3 not reproduced.")
                except json.JSONDecodeError:
                    log_problem_reproduced(f"/rpc/refresh (client-side simulation) returned 200 OK but with a non-JSON body: {response.text}")
                except (IndexError, TypeError):
                    log_problem_reproduced(f"/rpc/refresh (client-side simulation) returned 200 OK but with unexpected JSON structure: {response.text}")
            else: # This 'else' correctly pairs with the if/elif for status codes.
                log_failure_condition(f"/rpc/refresh (client-side simulation with valid cookie) returned unexpected status {response.status_code}. Body: {response.text}")
        except requests.RequestException as e:
            log_error_critical(f"Client refresh simulation (valid cookie) request exception: {e}")

    # Scenario: No cookies sent
    log_info("\nTesting Problem 3 variant: /rpc/refresh with NO cookies...")
    no_cookie_session = requests.Session()
    try:
        response_no_cookies = no_cookie_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
        debug_info(f"Refresh (no cookies) response status: {response_no_cookies.status_code}")
        debug_info(f"Refresh (no cookies) response body: {response_no_cookies.text}")
        if response_no_cookies.status_code == 401:
            log_success_condition("/rpc/refresh with no cookies correctly returned 401.")
            try:
                data = response_no_cookies.json()
                actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                if actual_data.get("error_code") == "REFRESH_NO_TOKEN_COOKIE":
                    log_success_condition(f"  Error code REFRESH_NO_TOKEN_COOKIE received as expected.")
                else:
                    log_failure_condition(f"  Expected error_code REFRESH_NO_TOKEN_COOKIE, got: {actual_data.get('error_code')}. Full response: {actual_data}")
            except (json.JSONDecodeError, IndexError, TypeError):
                log_failure_condition(f"  Could not parse error_code from 401 response. Body: {response_no_cookies.text}")
        else:
            log_problem_reproduced(f"/rpc/refresh with no cookies returned {response_no_cookies.status_code} instead of 401. Body: {response_no_cookies.text}")
    except requests.RequestException as e:
        log_error_critical(f"Refresh (no cookies) request exception: {e}")

    # Scenario: Only access token cookie sent, no refresh token cookie
    log_info("\nTesting Problem 3 variant: /rpc/refresh with ONLY access token cookie...")
    if initial_access_token: # From the main session login
        access_only_session = requests.Session()
        access_only_session.cookies.set("statbus", initial_access_token, domain="dev.statbus.org", path="/") # Simulate only access token
        debug_info(f"Cookies for access-only refresh attempt: {access_only_session.cookies.get_dict()}")
        try:
            response_access_only = access_only_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
            debug_info(f"Refresh (access only) response status: {response_access_only.status_code}")
            debug_info(f"Refresh (access only) response body: {response_access_only.text}")
            if response_access_only.status_code == 401:
                log_success_condition("/rpc/refresh with only access token cookie correctly returned 401.")
                try:
                    data = response_access_only.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    if actual_data.get("error_code") == "REFRESH_NO_TOKEN_COOKIE": # Or a more specific error if the backend can distinguish
                        log_success_condition(f"  Error code REFRESH_NO_TOKEN_COOKIE (or similar) received. Got: {actual_data.get('error_code')}")
                    else:
                        log_failure_condition(f"  Expected error_code REFRESH_NO_TOKEN_COOKIE, got: {actual_data.get('error_code')}. Full response: {actual_data}")
                except (json.JSONDecodeError, IndexError, TypeError):
                    log_failure_condition(f"  Could not parse error_code from 401 response. Body: {response_access_only.text}")
            else:
                log_problem_reproduced(f"/rpc/refresh with only access token cookie returned {response_access_only.status_code} instead of 401. Body: {response_access_only.text}")
        except requests.RequestException as e:
            log_error_critical(f"Refresh (access only) request exception: {e}")
    else:
        log_failure_condition("Skipping refresh with access-only cookie test: initial access token not available.")

    # Scenario: Refresh token cookie contains an access token (wrong type)
    log_info("\nTesting Problem 3 variant: /rpc/refresh with access token value in refresh_token cookie...")
    if initial_access_token: # Use the value of an access token
        wrong_type_session = requests.Session()
        # Put the access token's value into the statbus-refresh cookie
        wrong_type_session.cookies.set("statbus-refresh", initial_access_token, domain="dev.statbus.org", path="/")
        debug_info(f"Cookies for wrong-type refresh attempt: {wrong_type_session.cookies.get_dict()}")
        try:
            response_wrong_type = wrong_type_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
            debug_info(f"Refresh (wrong type) response status: {response_wrong_type.status_code}")
            debug_info(f"Refresh (wrong type) response body: {response_wrong_type.text}")
            if response_wrong_type.status_code == 401:
                log_success_condition("/rpc/refresh with access token as refresh token correctly returned 401.")
                try:
                    data = response_wrong_type.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    if actual_data.get("error_code") == "REFRESH_INVALID_TOKEN_TYPE":
                        log_success_condition(f"  Error code REFRESH_INVALID_TOKEN_TYPE received as expected.")
                    else:
                        log_failure_condition(f"  Expected error_code REFRESH_INVALID_TOKEN_TYPE, got: {actual_data.get('error_code')}. Full response: {actual_data}")
                except (json.JSONDecodeError, IndexError, TypeError):
                    log_failure_condition(f"  Could not parse error_code from 401 response. Body: {response_wrong_type.text}")
            else:
                log_problem_reproduced(f"/rpc/refresh with access token as refresh token returned {response_wrong_type.status_code} instead of 401. Body: {response_wrong_type.text}")
        except requests.RequestException as e:
            log_error_critical(f"Refresh (wrong type) request exception: {e}")
    else:
        log_failure_condition("Skipping refresh with wrong-type cookie test: initial access token not available for simulation.")

def test_nextjs_api_auth_test(session: Session):
    log_info("\nTesting Next.js /api/auth_test endpoint...")
    if not session.cookies.get("statbus"): # Refresh cookie might not be sent by browser to /api/auth_test due to path
        log_failure_condition("Skipping /api/auth_test: Missing 'statbus' access token cookie from login session.")
        return

    log_queue = queue.Queue()
    # Assuming SSH target and remote directory are fixed for this specific test script
    ssh_target = "statbus_dev@statbus.org" 
    remote_command_dir = "statbus" # The directory where 'docker compose' commands are run on the remote server
    services_to_log = ["app", "db"]

    log_collector = RemoteLogCollector(ssh_target, remote_command_dir, services_to_log, log_queue)
    
    remote_logs_header_printed = False

    try:
        log_collector.start()
        
        api_url = f"{DEV_API_URL}/api/auth_test"
        log_info(f"Calling {api_url} with current session cookies...")
        response = session.get(api_url, timeout=20) # Increased timeout slightly for remote call + logging
        
        debug_info(f"/api/auth_test response status: {response.status_code}")
        
        if response.status_code == 200:
            try:
                data = response.json()
                log_info(f"/api/auth_test response JSON: {json.dumps(data, indent=2)}")
                
                # Basic checks on the structure
                if "postgrest_js_call_to_rpc_auth_test" not in data or \
                   "direct_fetch_call_to_rpc_auth_test" not in data:
                    log_problem_reproduced("/api/auth_test response missing key sections.")
                else:
                    log_success_condition("/api/auth_test responded successfully. Detailed analysis of JSON needed.")
                    
                    # Detailed check for cookies seen by DB
                    pg_js_call_data = data.get("postgrest_js_call_to_rpc_auth_test", {}).get("data", {})
                    direct_fetch_call_data = data.get("direct_fetch_call_to_rpc_auth_test", {}).get("data", {})

                    pg_js_cookies_seen_by_db = pg_js_call_data.get("cookies") if isinstance(pg_js_call_data, dict) else None
                    direct_fetch_cookies_seen_by_db = direct_fetch_call_data.get("cookies") if isinstance(direct_fetch_call_data, dict) else None
                    
                    if pg_js_cookies_seen_by_db is not None: # Check for None explicitly, as empty {} is valid
                        log_info(f"Cookies seen by DB (PostgREST-JS call to rpc/auth_test): {json.dumps(pg_js_cookies_seen_by_db)}")
                    else:
                        log_failure_condition("Could not extract cookies seen by DB from PostgREST-JS call in /api/auth_test response.")

                    if direct_fetch_cookies_seen_by_db is not None:
                        log_info(f"Cookies seen by DB (Direct Fetch call to rpc/auth_test): {json.dumps(direct_fetch_cookies_seen_by_db)}")
                    else:
                        log_failure_condition("Could not extract cookies seen by DB from Direct Fetch call in /api/auth_test response.")

            except json.JSONDecodeError:
                log_problem_reproduced(f"/api/auth_test returned non-JSON response: {response.text}")
        else:
            log_failure_condition(f"/api/auth_test call failed with status {response.status_code}. Body: {response.text}")

    except requests.RequestException as e:
        log_error_critical(f"/api/auth_test request exception: {e}")
    finally:
        log_collector.stop()
        # Print collected remote logs
        if not log_queue.empty():
            print(f"\n{BLUE}--- Collected Remote Logs for /api/auth_test call ---{NC}")
            remote_logs_header_printed = True
            while not log_queue.empty():
                try:
                    log_line = log_queue.get_nowait()
                    print(log_line)
                except queue.Empty:
                    break
            print(f"{BLUE}--- End of Remote Logs ---{NC}\n")
        elif not remote_logs_header_printed : # If no logs, but header wasn't printed (e.g. collector failed to start)
            log_info("No remote logs were collected or collector did not start properly.")

def fetch_dev_credentials() -> bool:
    """Fetches credentials for the first user from remote .users.yml."""
    global USER_EMAIL, USER_PASSWORD
    log_info("Fetching credentials from dev.statbus.org .users.yml...")
    ssh_target = "statbus_dev@statbus.org"
    # Fetch first 3 lines which should contain the first user's details
    command_str = "head -n 3 statbus/.users.yml" 
    ssh_command = ['ssh', ssh_target, command_str]

    try:
        result = subprocess.run(
            ssh_command,
            capture_output=True,
            text=True,
            check=True,
            timeout=10
        )
        yaml_content = result.stdout.strip()
        debug_info(f"Raw YAML content from remote: \n{yaml_content}")
        
        # The output is a list item, ensure it's parsed as such
        # PyYAML expects a full document, so ensure the snippet is valid
        # If head -n 3 gives "- email: ...\n  role: ...\n  password: ...", it's a valid snippet for a list item
        if not yaml_content.startswith("-"): # Basic check if it looks like a list item start
            # Try to make it a valid list if it's just the attributes
            yaml_content = "- " + yaml_content.replace("\n", "\n  ")

        users = yaml.safe_load(yaml_content)
        
        if users and isinstance(users, list) and len(users) > 0:
            first_user = users[0]
            if isinstance(first_user, dict) and "email" in first_user and "password" in first_user:
                USER_EMAIL = first_user["email"]
                USER_PASSWORD = first_user["password"]
                log_success_condition(f"Successfully fetched credentials for user: {USER_EMAIL}")
                return True
            else:
                log_failure_condition(f"Could not parse first user's email/password from YAML: {first_user}")
        else:
            log_failure_condition(f"Could not parse users from YAML content: {users}")
            
    except subprocess.CalledProcessError as e:
        log_failure_condition(f"SSH command failed: {e}. Stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        log_failure_condition("SSH command timed out.")
    except yaml.YAMLError as e:
        log_failure_condition(f"Failed to parse YAML from .users.yml: {e}. Content: \n{yaml_content}")
    except Exception as e:
        log_failure_condition(f"An unexpected error occurred while fetching credentials: {e}")
    
    return False

def main_dev_tests():
    log_info("=== Starting Authentication Tests against dev.statbus.org ===")
    
    if not fetch_dev_credentials():
        log_error_critical("Failed to fetch credentials from dev.statbus.org. Aborting tests.")
        return

    if not USER_EMAIL or not USER_PASSWORD: # Should be set by fetch_dev_credentials
        log_error_critical("USER_EMAIL or USER_PASSWORD not set after attempting to fetch them.")
        return

    # Test 1 & 2 require a logged-in session
    session_problem1_2 = requests.Session()
    login_details = login_user(session_problem1_2)
    
    initial_access_token = None
    initial_refresh_token = None

    if login_details:
        initial_access_token = login_details.get("access")
        initial_refresh_token = login_details.get("refresh")
        debug_info(f"Initial access token (from cookie): {'Present' if initial_access_token else 'Missing'}")
        debug_info(f"Initial refresh token (from cookie): {'Present' if initial_refresh_token else 'Missing'}")
    else:
        log_failure_condition("Login failed. Subsequent tests for problems 1, 2, and 3 might not be meaningful or will be skipped.")

    # Test Problem 1: /rpc/auth_status malfunction
    # This test uses the cookies from the login.
    test_dev_auth_status_malfunction(session_problem1_2, initial_access_token)

    # Test Problem 2: /rpc/refresh malfunction (missing Set-Cookie / empty body)
    # This test also uses the cookies from the initial login.
    test_dev_refresh_malfunction(session_problem1_2, initial_refresh_token)
    
    # Test Problem 3: Client-side /rpc/refresh failure (401 response) and variants
    # The initial login for Problem 1 & 2 provides the access_token needed for some variants here.
    # A re-login is done to ensure a clean session with a known valid refresh token for the first part of Problem 3.
    log_info("\nRe-logging in for main Problem 3 test (valid refresh cookie)...")
    session_problem3_main = requests.Session()
    login_details_for_p3_main = login_user(session_problem3_main)
    refresh_token_for_p3_main = login_details_for_p3_main.get("refresh") if login_details_for_p3_main else None
    
    # Pass the initial_access_token from the first login for use in variants
    if login_details_for_p3_main and refresh_token_for_p3_main:
        test_dev_client_refresh_failure(session_problem3_main, refresh_token_for_p3_main, initial_access_token)
    else:
        log_failure_condition("Skipping Problem 3 tests as re-login for main scenario failed or refresh token was not obtained.")

    # Call the new test for /api/auth_test using the session from the first successful login
    # This session (session_problem1_2) should have the necessary cookies for dev.statbus.org
    if login_details: # Ensure the very first login was successful
        test_nextjs_api_auth_test(session_problem1_2)
    else:
        log_failure_condition("Skipping /api/auth_test call because initial login failed.")

    log_info("\n=== Dev Authentication Tests Finished ===")
    if PROBLEM_REPRODUCED_FLAG:
        log_info(f"{RED}One or more authentication problems from auth-problem.md WERE REPRODUCED against {DEV_API_URL}.{NC}")
        sys.exit(1) # Exit with error if problems were found
    else:
        log_info(f"{GREEN}No authentication problems from auth-problem.md were reproduced against {DEV_API_URL}. All checks passed.{NC}")
        sys.exit(0) # Exit successfully if no problems were found

if __name__ == "__main__":
    main_dev_tests()
