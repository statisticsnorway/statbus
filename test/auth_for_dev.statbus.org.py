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
from typing import Optional, Dict, Any, List, Tuple
import subprocess
import threading
import time
import queue
import yaml
import traceback # Added for exception formatting
import atexit # For global cleanup
from datetime import datetime, timezone # For script start timestamp

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

# Configuration
DEV_API_URL = "https://dev.statbus.org" # Target the dev environment
USER_EMAIL = None # Will be fetched
USER_PASSWORD = None # Will be fetched

# Global flag to track if any problem was *specifically tested for and* reproduced
PROBLEM_REPRODUCED_FLAG = False
# Global flag for *any* test failure or unhandled exception
OVERALL_TEST_FAILURE_FLAG = False

IS_DEBUG_ENABLED = os.environ.get("DEBUG", "false").lower() == "true"

# Global log collector and queue, and services it will collect for
GLOBAL_REMOTE_LOG_COLLECTOR: Optional['RemoteLogCollector'] = None
GLOBAL_REMOTE_LOG_QUEUE: Optional[queue.Queue] = None
GLOBAL_REMOTE_SERVICES_TO_COLLECT = ["app", "db", "proxy", "rest"] # Services on the remote dev server
SCRIPT_START_TIMESTAMP_RFC3339: Optional[str] = None


class TestContext:
    def __init__(self, name: str): # services_to_log, ssh_target, remote_command_dir removed
        self.name = name
        self.log_buffer: List[Tuple[str, str]] = [] # List of (level, message)
        self.is_failed = False
        # log_collector and remote_log_queue are now global

    def _add_log(self, level: str, message: str):
        self.log_buffer.append((level, message))

    def info(self, message: str): self._add_log("INFO", message)
    def success(self, message: str): self._add_log("SUCCESS", message)
    def warning(self, message: str): self._add_log("WARNING", message)
    
    def debug(self, message: str):
        if IS_DEBUG_ENABLED:
            self._add_log("DEBUG", message)

    def error(self, message: str):
        global OVERALL_TEST_FAILURE_FLAG
        OVERALL_TEST_FAILURE_FLAG = True
        self.is_failed = True
        self._add_log("ERROR", message)

    def problem_reproduced(self, message: str):
        global PROBLEM_REPRODUCED_FLAG, OVERALL_TEST_FAILURE_FLAG
        PROBLEM_REPRODUCED_FLAG = True
        OVERALL_TEST_FAILURE_FLAG = True 
        self.is_failed = True
        self._add_log("PROBLEM_REPRODUCED", message)

    def problem_identified(self, message: str): # For less severe than reproduced
        self._add_log("PROBLEM_IDENTIFIED", message)

    def add_detail(self, detail_message: str):
        self._add_log("DETAIL", detail_message)

    def __enter__(self):
        global GLOBAL_REMOTE_LOG_COLLECTOR, GLOBAL_REMOTE_LOG_QUEUE
        if GLOBAL_REMOTE_LOG_COLLECTOR and GLOBAL_REMOTE_LOG_QUEUE:
            # Drain and discard logs accumulated before this context started
            discarded_count = 0
            while not GLOBAL_REMOTE_LOG_QUEUE.empty():
                try:
                    GLOBAL_REMOTE_LOG_QUEUE.get_nowait()
                    discarded_count += 1
                except queue.Empty:
                    break
            if IS_DEBUG_ENABLED and discarded_count > 0:
                self.debug(f"Discarded {discarded_count} pre-existing remote Docker log lines before context '{self.name}' processing.")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        global GLOBAL_REMOTE_LOG_COLLECTOR, GLOBAL_REMOTE_LOG_QUEUE, IS_DEBUG_ENABLED
        
        collected_docker_logs_for_this_context = []
        if GLOBAL_REMOTE_LOG_COLLECTOR and GLOBAL_REMOTE_LOG_QUEUE:
            while not GLOBAL_REMOTE_LOG_QUEUE.empty():
                try:
                    log_line = GLOBAL_REMOTE_LOG_QUEUE.get_nowait()
                    collected_docker_logs_for_this_context.append(log_line)
                except queue.Empty:
                    break
        
        if collected_docker_logs_for_this_context:
            self._add_log("DOCKER_LOGS_HEADER", f"--- Remote Docker Logs for {self.name} (all services collected during context) ---")
            for line in collected_docker_logs_for_this_context:
                self._add_log("DOCKER_LOG", line)
            self._add_log("DOCKER_LOGS_FOOTER", f"--- End Remote Docker Logs for {self.name} ---")

        if exc_type is not None: # Unhandled exception
            if not self.is_failed:
                global OVERALL_TEST_FAILURE_FLAG
                OVERALL_TEST_FAILURE_FLAG = True
                self.is_failed = True
            exc_info_str = "".join(traceback.format_exception(exc_type, exc_val, exc_tb))
            self._add_log("EXCEPTION", f"Unhandled exception in context '{self.name}':\n{exc_info_str}")

        if self.is_failed or IS_DEBUG_ENABLED:
            print(f"\n{BLUE}--- Logs for Test Context: {self.name} ({'FAILED' if self.is_failed else 'DEBUG'}) ---{NC}")
            for level, message in self.log_buffer:
                color = NC
                prefix = ""
                if level == "ERROR" or level == "EXCEPTION": color, prefix = RED, "✗ ERROR: "
                elif level == "SUCCESS": color, prefix = GREEN, "✓ SUCCESS: "
                elif level == "WARNING": color, prefix = YELLOW, "WARN: "
                elif level == "INFO": color, prefix = BLUE, "INFO: "
                elif level == "DEBUG": color, prefix = YELLOW, "DEBUG: "
                elif level == "PROBLEM_REPRODUCED": color, prefix = RED, "PROBLEM REPRODUCED: "
                elif level == "PROBLEM_IDENTIFIED": color, prefix = YELLOW, "PROBLEM IDENTIFIED: "
                elif level == "DOCKER_LOGS_HEADER": color = BLUE
                elif level == "DOCKER_LOGS_FOOTER": color = BLUE
                elif level == "DOCKER_LOG": color = NC 
                elif level == "DETAIL": color, prefix = RED, "  Detail: "

                for i, line in enumerate(message.splitlines()):
                    if i == 0:
                        print(f"{color}{prefix}{line}{NC}")
                    else:
                        if level in ["DETAIL", "EXCEPTION", "DOCKER_LOG"]:
                             print(f"{color}{line}{NC}")
                        else:
                             print(f"{color}{' ' * len(prefix)}{line}{NC}")
            print(f"{BLUE}--- End Logs for Test Context: {self.name} ---{NC}\n")
        elif not self.is_failed and not IS_DEBUG_ENABLED:
            last_success_msg = f"Test Context '{self.name}' completed successfully."
            success_messages = [msg for lvl, msg in self.log_buffer if lvl == "SUCCESS"]
            if success_messages:
                last_success_msg = success_messages[-1]
            print(f"{GREEN}✓ {last_success_msg}{NC}")

# Stubs for old logging functions if called outside a context (should be minimal)
def log_info(message: str, ctx: Optional[TestContext] = None):
    if ctx: ctx.info(message)
    else: print(f"{BLUE}{message}{NC}")

def log_warning(message: str, ctx: Optional[TestContext] = None):
    if ctx: ctx.warning(message)
    else: print(f"{YELLOW}WARN: {message}{NC}")

def log_error_critical(message: str, ctx: Optional[TestContext] = None): # For critical script errors, not test failures
    if ctx: ctx.error(message) # Should ideally not happen for "critical" script errors
    else:
        global OVERALL_TEST_FAILURE_FLAG
        OVERALL_TEST_FAILURE_FLAG = True
        print(f"{RED}CRITICAL SCRIPT ERROR: {message}{NC}")
    # sys.exit(1) # Removed, main loop handles exit

def debug_info(message: str, ctx: Optional[TestContext] = None):
    if ctx: ctx.debug(message)
    elif IS_DEBUG_ENABLED: print(f"{YELLOW}DEBUG: {message}{NC}")


class RemoteLogCollector:
    def __init__(self, ssh_target: str, remote_command_dir: str, services: list[str], log_queue: queue.Queue, since_timestamp: Optional[str] = None):
        self.ssh_target = ssh_target
        self.remote_command_dir = remote_command_dir
        self.services = services
        self.log_queue = log_queue
        self.since_timestamp = since_timestamp # RFC3339 or Unix timestamp
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
        
        logs_cmd_part = ["docker", "compose", "logs", "--follow"]
        if self.since_timestamp:
            logs_cmd_part.extend(["--since", self.since_timestamp])
        else: # Fallback if no timestamp, though we aim to always provide one
            logs_cmd_part.extend(["--since", "1s"])
            # Use direct print for collector's own operational warnings if no context
            print(f"{YELLOW}RemoteLogCollector started without a specific --since timestamp, defaulting to '1s'.{NC}")

        logs_cmd_part.extend(self.services)
        
        command_str = f"cd {self.remote_command_dir} && {' '.join(logs_cmd_part)}"
        ssh_command = ['ssh', self.ssh_target, command_str]
        
        if IS_DEBUG_ENABLED:
            print(f"{BLUE}Collector: Starting remote log collection: {' '.join(ssh_command)}{NC}")
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
        # Use direct print for collector's own operational messages
        if IS_DEBUG_ENABLED:
            print(f"{BLUE}Collector: Stopping remote log collection for {self.ssh_target}...{NC}")
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
        if IS_DEBUG_ENABLED:
            print(f"{BLUE}Collector: Remote log collection stopped for {self.ssh_target}.{NC}")

def login_user(session: Session, ctx: TestContext) -> Optional[Dict[str, str]]:
    """Logs in the user and returns cookies if successful."""
    ctx.info(f"Attempting login for {USER_EMAIL} at {DEV_API_URL}...")
    try:
        response = session.post(
            f"{DEV_API_URL}/rest/rpc/login",
            json={"email": USER_EMAIL, "password": USER_PASSWORD},
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        ctx.debug(f"Login response status: {response.status_code}")
        ctx.debug(f"Login response headers: {dict(response.headers)}")
        ctx.debug(f"Login response cookies: {response.cookies.get_dict()}")
        
        if response.status_code == 200:
            try:
                data = response.json()
                ctx.debug(f"Login response body: {json.dumps(data, indent=2)}")
                if data.get("is_authenticated"):
                    ctx.success(f"Login successful for {USER_EMAIL}.")
                    access_token = session.cookies.get("statbus")
                    refresh_token = session.cookies.get("statbus-refresh")
                    if not access_token:
                         ctx.warning("Access token (statbus cookie) not found after login.")
                    if not refresh_token:
                         ctx.warning("Refresh token (statbus-refresh cookie) not found after login.")
                    return {"access": access_token, "refresh": refresh_token, "full_session_cookies": session.cookies.get_dict()}
                else:
                    ctx.error(f"Login failed: is_authenticated is false. Response: {data}")
                    return None
            except json.JSONDecodeError:
                ctx.error(f"Login failed: Could not decode JSON response. Body: {response.text}")
                return None
        else:
            ctx.error(f"Login request failed with status {response.status_code}. Body: {response.text}")
            return None
    except requests.RequestException as e:
        ctx.error(f"Login request exception: {e}")
        return None

def test_dev_auth_status_malfunction(session: Session, access_token_value: Optional[str], ctx: TestContext):
    """
    Tests Problem 1 from auth-problem.md: Server-side rpc/auth_status malfunction.
    Expected problem: returns data: null or is_authenticated: false for a valid token.
    """
    ctx.info("Testing Problem 1: /rest/rpc/auth_status malfunction...")
    if not access_token_value:
        ctx.warning("Skipping auth_status test: No access token provided (login likely failed).")
        return

    try:
        # The /rest/rpc/auth_status endpoint primarily relies on the JWT being passed by PostgREST
        # from the cookie, which the session object handles.
        # Forcing Authorization header might also work if PostgREST is configured for it.
        # Let's rely on the session cookie first, as that's closer to browser behavior.
        response = session.get(f"{DEV_API_URL}/rest/rpc/auth_status", timeout=10)
        
        ctx.debug(f"auth_status response status: {response.status_code}")
        ctx.debug(f"auth_status response headers: {dict(response.headers)}")
        ctx.debug(f"auth_status response body: {response.text}")

        if response.status_code == 200:
            if not response.text or response.text.lower() == "null" or response.text == "[]":
                ctx.problem_reproduced(f"/rest/rpc/auth_status returned an empty or null body: '{response.text}'")
                return

            try:
                data = response.json()
                actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data

                if actual_data is None:
                    ctx.problem_reproduced("/rest/rpc/auth_status returned JSON null in the data part.")
                elif not actual_data.get("is_authenticated"):
                    ctx.problem_reproduced(f"/rest/rpc/auth_status returned is_authenticated:false. Full response: {actual_data}")
                else:
                    ctx.success(f"/rest/rpc/auth_status seems OK: is_authenticated is true. Response: {actual_data}")
            except json.JSONDecodeError:
                ctx.problem_reproduced(f"/rest/rpc/auth_status returned non-JSON response: {response.text}")
            except (IndexError, TypeError):
                 ctx.problem_reproduced(f"/rest/rpc/auth_status returned unexpected JSON structure: {response.text}")
        else:
            ctx.warning(f"/rest/rpc/auth_status call failed with status {response.status_code}. Body: {response.text}")

    except requests.RequestException as e:
        ctx.error(f"auth_status request exception: {e}")

def test_dev_refresh_malfunction(session: Session, initial_refresh_token: Optional[str], ctx: TestContext):
    """
    Tests Problem 2 from auth-problem.md: Server-side rpc/refresh malfunction.
    Expected problem: HTTP 200 OK, but no Set-Cookie headers and/or empty body.
    """
    ctx.info("Testing Problem 2: /rpc/refresh malfunction (missing Set-Cookie / empty body)...")
    if not initial_refresh_token:
        ctx.warning("Skipping refresh malfunction test: No initial refresh token (login likely failed or cookie missing).")
        return
    
    ctx.info("Simulating middleware refresh: calling /rpc/refresh with ONLY the refresh token cookie.")
    
    middleware_sim_session = requests.Session()
    if initial_refresh_token:
        middleware_sim_session.cookies.set("statbus-refresh", initial_refresh_token, domain=DEV_API_URL.split("//")[-1].split("/")[0], path="/")
        ctx.debug(f"Cookies for middleware-simulated refresh attempt: {middleware_sim_session.cookies.get_dict()}")
    else:
        ctx.warning("Cannot simulate middleware refresh: initial_refresh_token is missing.")
        return

    try:
        response = middleware_sim_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
        
        ctx.debug(f"Refresh response status (middleware simulation): {response.status_code}")
        ctx.debug(f"Refresh response headers: {dict(response.headers)}")
        ctx.debug(f"Refresh response body: {response.text}")

        reproduced_this_test = False
        if response.status_code == 200:
            set_cookie_header = response.headers.get("Set-Cookie")
            new_statbus_cookie = response.cookies.get("statbus")
            new_refresh_cookie = response.cookies.get("statbus-refresh")

            if not set_cookie_header and not new_statbus_cookie and not new_refresh_cookie:
                ctx.problem_reproduced("/rpc/refresh returned 200 OK but no Set-Cookie headers were found.")
                reproduced_this_test = True
            elif not new_statbus_cookie or not new_refresh_cookie:
                ctx.problem_reproduced(f"/rpc/refresh returned 200 OK but one or more auth cookies are missing from Set-Cookie. Statbus: {new_statbus_cookie is not None}, Statbus-Refresh: {new_refresh_cookie is not None}")
                reproduced_this_test = True
            else:
                 ctx.success("/rpc/refresh returned Set-Cookie headers as expected.")
                 ctx.debug(f"Set-Cookie from headers: {set_cookie_header}")
                 ctx.debug(f"Parsed cookies by requests: statbus='{new_statbus_cookie}', statbus-refresh='{new_refresh_cookie}'")

            if not response.text.strip():
                ctx.problem_reproduced("/rpc/refresh returned 200 OK but with an empty response body.")
                reproduced_this_test = True
            else:
                try:
                    data = response.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    if not actual_data.get("is_authenticated"):
                        ctx.problem_reproduced(f"/rpc/refresh returned 200 OK but with is_authenticated:false. Body: {actual_data}")
                        reproduced_this_test = True
                    else:
                        ctx.success("/rpc/refresh returned 200 OK with a non-empty body and is_authenticated:true as expected.")
                        ctx.debug(f"Refresh response JSON: {json.dumps(actual_data, indent=2)}")
                except json.JSONDecodeError:
                    ctx.problem_reproduced(f"/rpc/refresh returned 200 OK but with a non-JSON body: {response.text}")
                    reproduced_this_test = True
            
            if not reproduced_this_test:
                ctx.success("Problem 2 (refresh malfunction) not reproduced. Refresh seems to work as expected.")
        else:
            ctx.warning(f"/rpc/refresh call failed with status {response.status_code}, expected 200 OK for this test. Body: {response.text}")

    except requests.RequestException as e:
        ctx.error(f"Refresh request exception: {e}")

def test_dev_client_refresh_failure(session: Session, initial_refresh_token: Optional[str], initial_access_token: Optional[str], ctx: TestContext):
    """
    Tests Problem 3 from auth-problem.md: Client-side rpc/refresh failure (returns 401),
    and variants with missing/incorrect cookies.
    
    Args:
        session: The requests.Session object, typically after a successful login (for the first scenario).
        initial_refresh_token: The refresh token string from a successful login.
        initial_access_token: The access token string from a successful login (used for variant tests).
    """
    ctx.info("Testing Problem 3: Client-side /rpc/refresh failure (401 response with valid refresh cookie)...")
    if not initial_refresh_token:
        ctx.warning("Skipping main client refresh failure test: No initial refresh token provided.")
    else:
        ctx.info("Attempting direct call to /rpc/refresh (simulating client-side refresh attempt with valid refresh cookie)...")
        ctx.debug(f"Cookies before client refresh attempt (valid): {session.cookies.get_dict()}")
        try:
            response = session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
            
            ctx.debug(f"Client refresh attempt response status (valid): {response.status_code}")
            ctx.debug(f"Client refresh attempt response body: {response.text}")

            if response.status_code == 401:
                ctx.problem_reproduced(f"/rpc/refresh (client-side simulation) returned 401 Unauthorized.")
            elif response.status_code == 200:
                set_cookie_header = response.headers.get("Set-Cookie")
                try:
                    data = response.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    
                    if not set_cookie_header or not response.text.strip() or not actual_data.get("is_authenticated"):
                        ctx.warning(f"/rpc/refresh (client-side simulation) returned 200 OK, but might exhibit Problem 2 symptoms (missing cookies/body). This test is for 401.")
                        ctx.debug("This scenario might mean Problem 3 is NOT reproduced, but Problem 2 IS.")
                    else:
                        ctx.success(f"/rpc/refresh (client-side simulation) returned 200 OK and seems to have worked. Problem 3 not reproduced.")
                except json.JSONDecodeError:
                    ctx.problem_reproduced(f"/rpc/refresh (client-side simulation) returned 200 OK but with a non-JSON body: {response.text}")
                except (IndexError, TypeError):
                    ctx.problem_reproduced(f"/rpc/refresh (client-side simulation) returned 200 OK but with unexpected JSON structure: {response.text}")
            else:
                ctx.warning(f"/rpc/refresh (client-side simulation with valid cookie) returned unexpected status {response.status_code}. Body: {response.text}")
        except requests.RequestException as e:
            ctx.error(f"Client refresh simulation (valid cookie) request exception: {e}")

    ctx.info("Testing Problem 3 variant: /rpc/refresh with NO cookies...")
    no_cookie_session = requests.Session()
    try:
        response_no_cookies = no_cookie_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
        ctx.debug(f"Refresh (no cookies) response status: {response_no_cookies.status_code}")
        ctx.debug(f"Refresh (no cookies) response body: {response_no_cookies.text}")
        if response_no_cookies.status_code == 401:
            ctx.success("/rpc/refresh with no cookies correctly returned 401.")
            try:
                data = response_no_cookies.json()
                actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                if actual_data.get("error_code") == "REFRESH_NO_TOKEN_COOKIE":
                    ctx.success(f"  Error code REFRESH_NO_TOKEN_COOKIE received as expected.")
                else:
                    ctx.warning(f"  Expected error_code REFRESH_NO_TOKEN_COOKIE, got: {actual_data.get('error_code')}. Full response: {actual_data}")
            except (json.JSONDecodeError, IndexError, TypeError):
                ctx.warning(f"  Could not parse error_code from 401 response. Body: {response_no_cookies.text}")
        else:
            ctx.problem_reproduced(f"/rpc/refresh with no cookies returned {response_no_cookies.status_code} instead of 401. Body: {response_no_cookies.text}")
    except requests.RequestException as e:
        ctx.error(f"Refresh (no cookies) request exception: {e}")

    ctx.info("Testing Problem 3 variant: /rpc/refresh with ONLY access token cookie...")
    if initial_access_token:
        access_only_session = requests.Session()
        access_only_session.cookies.set("statbus", initial_access_token, domain="dev.statbus.org", path="/")
        ctx.debug(f"Cookies for access-only refresh attempt: {access_only_session.cookies.get_dict()}")
        try:
            response_access_only = access_only_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
            ctx.debug(f"Refresh (access only) response status: {response_access_only.status_code}")
            ctx.debug(f"Refresh (access only) response body: {response_access_only.text}")
            if response_access_only.status_code == 401:
                ctx.success("/rpc/refresh with only access token cookie correctly returned 401.")
                try:
                    data = response_access_only.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    if actual_data.get("error_code") == "REFRESH_NO_TOKEN_COOKIE":
                        ctx.success(f"  Error code REFRESH_NO_TOKEN_COOKIE (or similar) received. Got: {actual_data.get('error_code')}")
                    else:
                        ctx.warning(f"  Expected error_code REFRESH_NO_TOKEN_COOKIE, got: {actual_data.get('error_code')}. Full response: {actual_data}")
                except (json.JSONDecodeError, IndexError, TypeError):
                    ctx.warning(f"  Could not parse error_code from 401 response. Body: {response_access_only.text}")
            else:
                ctx.problem_reproduced(f"/rpc/refresh with only access token cookie returned {response_access_only.status_code} instead of 401. Body: {response_access_only.text}")
        except requests.RequestException as e:
            ctx.error(f"Refresh (access only) request exception: {e}")
    else:
        ctx.warning("Skipping refresh with access-only cookie test: initial access token not available.")

    ctx.info("Testing Problem 3 variant: /rpc/refresh with access token value in refresh_token cookie...")
    if initial_access_token:
        wrong_type_session = requests.Session()
        wrong_type_session.cookies.set("statbus-refresh", initial_access_token, domain="dev.statbus.org", path="/")
        ctx.debug(f"Cookies for wrong-type refresh attempt: {wrong_type_session.cookies.get_dict()}")
        try:
            response_wrong_type = wrong_type_session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={}, timeout=10)
            ctx.debug(f"Refresh (wrong type) response status: {response_wrong_type.status_code}")
            ctx.debug(f"Refresh (wrong type) response body: {response_wrong_type.text}")
            if response_wrong_type.status_code == 401:
                ctx.success("/rpc/refresh with access token as refresh token correctly returned 401.")
                try:
                    data = response_wrong_type.json()
                    actual_data = data[0] if isinstance(data, list) and len(data) == 1 else data
                    if actual_data.get("error_code") == "REFRESH_INVALID_TOKEN_TYPE":
                        ctx.success(f"  Error code REFRESH_INVALID_TOKEN_TYPE received as expected.")
                    else:
                        ctx.warning(f"  Expected error_code REFRESH_INVALID_TOKEN_TYPE, got: {actual_data.get('error_code')}. Full response: {actual_data}")
                except (json.JSONDecodeError, IndexError, TypeError):
                    ctx.warning(f"  Could not parse error_code from 401 response. Body: {response_wrong_type.text}")
            else:
                ctx.problem_reproduced(f"/rpc/refresh with access token as refresh token returned {response_wrong_type.status_code} instead of 401. Body: {response_wrong_type.text}")
        except requests.RequestException as e:
            ctx.error(f"Refresh (wrong type) request exception: {e}")
    else:
        ctx.warning("Skipping refresh with wrong-type cookie test: initial access token not available for simulation.")

def test_dev_auth_test_direct_calls(session: Session, access_token_value: Optional[str], ctx: TestContext):
    ctx.info("Testing direct calls to /rest/rpc/auth_test (GET and POST)...")
    if not access_token_value:
        ctx.warning("Skipping direct auth_test calls: No access token (login likely failed).")
        return

    ctx.info("Attempting GET /rest/rpc/auth_test...")
    try:
        response_get = session.get(f"{DEV_API_URL}/rest/rpc/auth_test", timeout=10)
        ctx.debug(f"GET auth_test response status: {response_get.status_code}")
        ctx.debug(f"GET auth_test response body: {response_get.text}")

        if response_get.status_code == 200:
            try:
                data_get = response_get.json()
                actual_data_get = data_get[0] if isinstance(data_get, list) and len(data_get) == 1 else data_get
                
                # The top-level 'claims' in auth_test reflects current_setting('request.jwt.claims'), which is 'anon' role.
                # The actual user identity from the JWT is in 'access_token.claims'.
                access_token_claims_get = actual_data_get.get("access_token", {}).get("claims", {}) if actual_data_get else {}
                user_email_in_jwt_get = access_token_claims_get.get("email")

                if actual_data_get and user_email_in_jwt_get == USER_EMAIL:
                    ctx.success(f"GET /rest/rpc/auth_test successful. Access token claims verified for {USER_EMAIL}.")
                    ctx.debug(f"GET auth_test response JSON: {json.dumps(actual_data_get, indent=2)}")
                    # Optionally, verify the top-level GUC claims if that's also part of the test's intent
                    top_level_guc_claims_get = actual_data_get.get("claims", {})
                    if top_level_guc_claims_get.get("role") == "anon":
                        ctx.debug("  Top-level GUC claims correctly show 'anon' role as expected for auth_test.")
                    else:
                        ctx.warning(f"  Top-level GUC claims in auth_test unexpectedly show role: {top_level_guc_claims_get.get('role')}")
                else:
                    ctx.problem_reproduced(f"GET /rest/rpc/auth_test response data malformed or access token claims incorrect. Expected email {USER_EMAIL}, got {user_email_in_jwt_get}. Data: {actual_data_get}")
            except json.JSONDecodeError:
                ctx.problem_reproduced(f"GET /rest/rpc/auth_test returned non-JSON response: {response_get.text}")
            except (IndexError, TypeError) as e:
                ctx.problem_reproduced(f"GET /rest/rpc/auth_test returned unexpected JSON structure: {response_get.text}. Error: {e}")
        else:
            ctx.warning(f"GET /rest/rpc/auth_test call failed with status {response_get.status_code}. Body: {response_get.text}")
    except requests.RequestException as e:
        ctx.error(f"GET /rest/rpc/auth_test request exception: {e}")

    ctx.info("Attempting POST /rest/rpc/auth_test...")
    try:
        headers_post = {"Content-Type": "application/json"}
        response_post = session.post(f"{DEV_API_URL}/rest/rpc/auth_test", headers=headers_post, json={}, timeout=10)
        ctx.debug(f"POST auth_test response status: {response_post.status_code}")
        ctx.debug(f"POST auth_test response body: {response_post.text}")

        if response_post.status_code == 200:
            try:
                data_post = response_post.json()
                actual_data_post = data_post[0] if isinstance(data_post, list) and len(data_post) == 1 else data_post

                # The top-level 'claims' in auth_test reflects current_setting('request.jwt.claims'), which is 'anon' role.
                # The actual user identity from the JWT is in 'access_token.claims'.
                access_token_claims_post = actual_data_post.get("access_token", {}).get("claims", {}) if actual_data_post else {}
                user_email_in_jwt_post = access_token_claims_post.get("email")

                if actual_data_post and user_email_in_jwt_post == USER_EMAIL:
                    ctx.success(f"POST /rest/rpc/auth_test successful. Access token claims verified for {USER_EMAIL}.")
                    ctx.debug(f"POST auth_test response JSON: {json.dumps(actual_data_post, indent=2)}")
                    # Optionally, verify the top-level GUC claims
                    top_level_guc_claims_post = actual_data_post.get("claims", {})
                    if top_level_guc_claims_post.get("role") == "anon":
                        ctx.debug("  Top-level GUC claims correctly show 'anon' role as expected for auth_test.")
                    else:
                        ctx.warning(f"  Top-level GUC claims in auth_test unexpectedly show role: {top_level_guc_claims_post.get('role')}")
                else:
                    ctx.problem_reproduced(f"POST /rest/rpc/auth_test response data malformed or access token claims incorrect. Expected email {USER_EMAIL}, got {user_email_in_jwt_post}. Data: {actual_data_post}")
            except json.JSONDecodeError:
                ctx.problem_reproduced(f"POST /rest/rpc/auth_test returned non-JSON response: {response_post.text}")
            except (IndexError, TypeError) as e:
                ctx.problem_reproduced(f"POST /rest/rpc/auth_test returned unexpected JSON structure: {response_post.text}. Error: {e}")
        else:
            ctx.warning(f"POST /rest/rpc/auth_test call failed with status {response_post.status_code}. Body: {response_post.text}")
    except requests.RequestException as e:
        ctx.error(f"POST /rest/rpc/auth_test request exception: {e}")

def test_nextjs_api_auth_test(session: Session, ctx: TestContext): # Added ctx
    ctx.info("Testing Next.js /api/auth_test endpoint...")
    # RemoteLogCollector is now managed by TestContext if services_to_log is provided.
    # No need to create log_queue or log_collector here.
    
    if not session.cookies.get("statbus"):
        ctx.warning("Skipping /api/auth_test: Missing 'statbus' access token cookie from login session.")
        return

    # The TestContext (ctx) should have started the RemoteLogCollector if services_to_log were specified.
    # Logs will be collected and printed by TestContext.__exit__.

    try:
        api_url = f"{DEV_API_URL}/api/auth_test"
        ctx.info(f"Calling {api_url} with current session cookies...")
        response = session.get(api_url, timeout=20)
        
        ctx.debug(f"/api/auth_test response status: {response.status_code}")
        
        if response.status_code == 200:
            try:
                data = response.json()
                ctx.info(f"/api/auth_test response JSON (condensed): {json.dumps(data)[:200]}...")
                ctx.debug(f"/api/auth_test full response JSON: {json.dumps(data, indent=2)}")
                
                if "postgrest_js_call_to_rpc_auth_test" not in data or \
                   "direct_fetch_call_to_rpc_auth_test" not in data:
                    ctx.problem_reproduced("/api/auth_test response missing key sections.")
                else:
                    ctx.success("/api/auth_test responded successfully. Detailed analysis of JSON needed.")
                    
                    pg_js_call_data = data.get("postgrest_js_call_to_rpc_auth_test", {}).get("data", {})
                    direct_fetch_call_data = data.get("direct_fetch_call_to_rpc_auth_test", {}).get("data", {})

                    pg_js_cookies_seen_by_db = pg_js_call_data.get("cookies") if isinstance(pg_js_call_data, dict) else None
                    direct_fetch_cookies_seen_by_db = direct_fetch_call_data.get("cookies") if isinstance(direct_fetch_call_data, dict) else None
                    
                    if pg_js_cookies_seen_by_db is not None:
                        ctx.info(f"Cookies seen by DB (PostgREST-JS call to rpc/auth_test): {json.dumps(pg_js_cookies_seen_by_db)}")
                    else:
                        ctx.warning("Could not extract cookies seen by DB from PostgREST-JS call in /api/auth_test response.")

                    if direct_fetch_cookies_seen_by_db is not None:
                        ctx.info(f"Cookies seen by DB (Direct Fetch call to rpc/auth_test): {json.dumps(direct_fetch_cookies_seen_by_db)}")
                    else:
                        ctx.warning("Could not extract cookies seen by DB from Direct Fetch call in /api/auth_test response.")

            except json.JSONDecodeError:
                ctx.problem_reproduced(f"/api/auth_test returned non-JSON response: {response.text}")
        else:
            ctx.warning(f"/api/auth_test call failed with status {response.status_code}. Body: {response.text}")

    except requests.RequestException as e:
        ctx.error(f"/api/auth_test request exception: {e}")
    # No finally block for log_collector.stop() or printing logs; TestContext handles this.


def test_dev_expired_token_refresh_flow(session: Session, ctx: TestContext):
    """
    Tests the new, correct refresh flow on the dev server.
    1. Uses the provided logged-in session.
    2. Calls the dedicated RPC to expire the access token.
    3. Calls /rpc/auth_status, expects it to report unauthenticated but suggest a refresh.
    4. Calls /rpc/refresh.
    5. Verifies new tokens are issued and the user is now authenticated.
    """
    ctx.info("Testing the new expired token refresh flow...")

    original_access_token = session.cookies.get("statbus")
    original_refresh_token = session.cookies.get("statbus-refresh")
    if not original_refresh_token or not original_access_token:
        ctx.error("Could not retrieve original tokens from the provided session for expired token flow test.")
        return

    # 2. Call the RPC to expire the access token. This sets a new, expired 'statbus' cookie.
    ctx.info("Calling /rpc/auth_expire_access_keep_refresh to get an expired access token...")
    try:
        expire_response = session.post(f"{DEV_API_URL}/rest/rpc/auth_expire_access_keep_refresh", json={})
        if expire_response.status_code == 200:
            ctx.success("Successfully called auth_expire_access_keep_refresh.")
        else:
            ctx.error(f"Call to auth_expire_access_keep_refresh failed with status {expire_response.status_code}. Body: {expire_response.text}")
            return
    except Exception as e:
        ctx.error(f"Exception during auth_expire_access_keep_refresh call: {e}")
        return
    
    expired_access_token = session.cookies.get("statbus")
    if not expired_access_token or expired_access_token == original_access_token:
        ctx.error("auth_expire_access_keep_refresh did not set a new, different access token.")
        return

    # 3. Test /rpc/auth_status - expect it to suggest a refresh
    ctx.info("Testing /rpc/auth_status with the new expired access token...")
    try:
        auth_status_response = session.get(f"{DEV_API_URL}/rest/rpc/auth_status", timeout=10)
        if auth_status_response.status_code == 200:
            data = auth_status_response.json()
            # For GET requests, the data is the object itself
            actual_data = data
            auth_ok = actual_data.get("is_authenticated") is False
            refresh_ok = actual_data.get("expired_access_token_call_refresh") is True
            if auth_ok and refresh_ok:
                ctx.success("auth_status correctly returned is_authenticated=false and expired_access_token_call_refresh=true.")
            else:
                ctx.error(f"auth_status did not return the expected state for an expired token. Got: {actual_data}")
                return
        else:
            ctx.error(f"auth_status call with expired token failed with status {auth_status_response.status_code}")
            return
    except Exception as e:
        ctx.error(f"Exception during auth_status call with expired token: {e}")
        return

    # 4. Call /rpc/refresh, as the client would do
    ctx.info("Calling /rpc/refresh to get new tokens...")
    try:
        refresh_response = session.post(f"{DEV_API_URL}/rest/rpc/refresh", json={})
        if refresh_response.status_code == 200:
            ctx.success("Refresh call was successful.")
            refresh_data = refresh_response.json()
            actual_refresh_data = refresh_data[0] if isinstance(refresh_data, list) and len(refresh_data) == 1 else refresh_data
            if actual_refresh_data.get("is_authenticated"):
                ctx.success("Refresh response body confirms authentication.")
            else:
                ctx.error(f"Refresh response body indicates not authenticated. Body: {actual_refresh_data}")
                return
        else:
            ctx.error(f"Refresh call failed with status {refresh_response.status_code}. Body: {refresh_response.text}")
            return
    except Exception as e:
        ctx.error(f"Exception during refresh call: {e}")
        return

    # 5. Final check with auth_status
    ctx.info("Verifying authentication status after successful refresh...")
    try:
        final_status_response = session.get(f"{DEV_API_URL}/rest/rpc/auth_status", timeout=10)
        if final_status_response.status_code == 200:
            data = final_status_response.json()
            actual_data = data
            auth_ok = actual_data.get("is_authenticated") is True
            refresh_ok = actual_data.get("expired_access_token_call_refresh") is False
            if auth_ok and refresh_ok:
                ctx.success("Final auth_status check confirms user is authenticated.")
            else:
                ctx.error(f"Final auth_status check shows incorrect state. Got: {actual_data}")
        else:
            ctx.error(f"Final auth_status call failed with status {final_status_response.status_code}")
    except Exception as e:
        ctx.error(f"Exception during final auth_status call: {e}")


def fetch_dev_credentials(ctx: TestContext) -> bool: # Added ctx
    """Fetches credentials for the first user from remote .users.yml."""
    global USER_EMAIL, USER_PASSWORD
    ctx.info("Fetching credentials from dev.statbus.org .users.yml...")
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
        ctx.debug(f"Raw YAML content from remote: \n{yaml_content}")
        
        if not yaml_content.startswith("-"):
            yaml_content = "- " + yaml_content.replace("\n", "\n  ")

        users = yaml.safe_load(yaml_content)
        
        if users and isinstance(users, list) and len(users) > 0:
            first_user = users[0]
            if isinstance(first_user, dict) and "email" in first_user and "password" in first_user:
                USER_EMAIL = first_user["email"]
                USER_PASSWORD = first_user["password"]
                ctx.success(f"Successfully fetched credentials for user: {USER_EMAIL}")
                return True
            else:
                ctx.error(f"Could not parse first user's email/password from YAML: {first_user}")
        else:
            ctx.error(f"Could not parse users from YAML content: {users}")
            
    except subprocess.CalledProcessError as e:
        ctx.error(f"SSH command failed: {e}. Stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        ctx.error("SSH command timed out.")
    except yaml.YAMLError as e:
        ctx.error(f"Failed to parse YAML from .users.yml: {e}. Content: \n{yaml_content}")
    except Exception as e:
        ctx.error(f"An unexpected error occurred while fetching credentials: {e}")
    
    return False

# main_dev_tests is already updated in the user-provided file, so no changes needed here.
# The following is the start of the already updated main_dev_tests function.
# I am providing it here just to show where the fetch_dev_credentials function ends.
def main_dev_tests():
    global PROBLEM_REPRODUCED_FLAG, OVERALL_TEST_FAILURE_FLAG
    global SCRIPT_START_TIMESTAMP_RFC3339 # For log collector
    global GLOBAL_REMOTE_LOG_COLLECTOR, GLOBAL_REMOTE_LOG_QUEUE # For log collector
    
    SCRIPT_START_TIMESTAMP_RFC3339 = datetime.now(timezone.utc).isoformat()

    # Initial messages print directly
    print(f"{BLUE}=== Starting Authentication Tests against dev.statbus.org ==={NC}")
    if IS_DEBUG_ENABLED:
        print(f"{YELLOW}DEBUG mode is enabled.{NC}")

    # Initialize and start global remote log collector
    GLOBAL_REMOTE_LOG_QUEUE = queue.Queue()
    # Default SSH target and command directory for dev environment
    # These could be made configurable if needed (e.g., via env vars or args)
    ssh_target_for_logs = "statbus_dev@statbus.org"
    remote_command_dir_for_logs = "statbus"

    GLOBAL_REMOTE_LOG_COLLECTOR = RemoteLogCollector(
        ssh_target=ssh_target_for_logs,
        remote_command_dir=remote_command_dir_for_logs,
        services=GLOBAL_REMOTE_SERVICES_TO_COLLECT,
        log_queue=GLOBAL_REMOTE_LOG_QUEUE,
        since_timestamp=SCRIPT_START_TIMESTAMP_RFC3339
    )
    GLOBAL_REMOTE_LOG_COLLECTOR.start()
    atexit.register(lambda: GLOBAL_REMOTE_LOG_COLLECTOR.stop() if GLOBAL_REMOTE_LOG_COLLECTOR else None)

    initial_access_token = None
    initial_refresh_token = None
    login_details_ok = False

    with TestContext("Setup: Fetch Credentials and Initial Login") as ctx:
        if not fetch_dev_credentials(ctx):
            ctx.error("Failed to fetch credentials from dev.statbus.org. Aborting tests.")
            if not IS_DEBUG_ENABLED: sys.exit(1) # Exit early if critical setup fails and not debugging
            return # Stop further execution in main_dev_tests

        if not USER_EMAIL or not USER_PASSWORD:
            ctx.error("USER_EMAIL or USER_PASSWORD not set after attempting to fetch them.")
            if not IS_DEBUG_ENABLED: sys.exit(1)
            return

        session_initial_login = requests.Session()
        login_details = login_user(session_initial_login, ctx)
    
        if login_details:
            initial_access_token = login_details.get("access")
            initial_refresh_token = login_details.get("refresh")
            ctx.debug(f"Initial access token (from cookie): {'Present' if initial_access_token else 'Missing'}")
            ctx.debug(f"Initial refresh token (from cookie): {'Present' if initial_refresh_token else 'Missing'}")
            login_details_ok = True # Mark that login details were obtained
            # Keep session_initial_login alive for subsequent tests that need its cookies
        else:
            ctx.warning("Initial login failed. Subsequent tests might not be meaningful or will be skipped.")
            login_details_ok = False
            # session_initial_login is not useful if login failed

    # Proceed with tests only if initial setup (including login) was somewhat successful or if debugging
    if not login_details_ok and not IS_DEBUG_ENABLED:
        print(f"{RED}Exiting due to failure in initial login/setup.{NC}")
        sys.exit(1)

    # Use a new session for Problem 1 & 2 tests, but re-use tokens from initial login
    # Or, more simply, pass the session_initial_login if it was successful.
    # For clarity, let's assume session_initial_login is the one to use if login_details_ok.
    # If login failed, some tests will be skipped or might behave differently.

    with TestContext("Problem 1: Auth Status Malfunction") as ctx:
        # Create a fresh session for this test if needed, or use the one from initial login
        # For this test, it's better to use the session that just logged in.
        if login_details_ok:
             test_dev_auth_status_malfunction(session_initial_login, initial_access_token, ctx)
        else:
            ctx.warning("Skipping Problem 1 test due to initial login failure.")
    if OVERALL_TEST_FAILURE_FLAG and not IS_DEBUG_ENABLED: print(f"{RED}Exiting due to failure.{NC}"); sys.exit(1)

    with TestContext("Direct RPC Auth Test Calls") as ctx:
        if login_details_ok:
            test_dev_auth_test_direct_calls(session_initial_login, initial_access_token, ctx)
        else:
            ctx.warning("Skipping direct RPC auth_test calls due to initial login failure.")
    if OVERALL_TEST_FAILURE_FLAG and not IS_DEBUG_ENABLED: print(f"{RED}Exiting due to failure.{NC}"); sys.exit(1)

    with TestContext("Problem 2: Refresh Malfunction") as ctx:
        if login_details_ok: # Needs initial_refresh_token
            test_dev_refresh_malfunction(session_initial_login, initial_refresh_token, ctx)
        else:
            ctx.warning("Skipping Problem 2 test due to initial login failure or missing refresh token.")
    if OVERALL_TEST_FAILURE_FLAG and not IS_DEBUG_ENABLED: print(f"{RED}Exiting due to failure.{NC}"); sys.exit(1)
    
    # For Problem 3, a re-login is part of its specific test setup.
    # It also uses initial_access_token from the very first login for variants.
    with TestContext("Problem 3: Client Refresh Failure and Variants") as ctx_p3:
        ctx_p3.info("Re-logging in for main Problem 3 test (valid refresh cookie)...")
        session_problem3_main = requests.Session()
        # Use a sub-context for this login or log directly to ctx_p3
        login_details_for_p3_main = login_user(session_problem3_main, ctx_p3) # Pass current context
        
        if ctx_p3.is_failed: # Check if login within this context failed
             ctx_p3.warning("Re-login for Problem 3 main scenario failed. Some P3 tests might be skipped.")
             # test_dev_client_refresh_failure will handle missing refresh_token_for_p3_main
        
        refresh_token_for_p3_main = login_details_for_p3_main.get("refresh") if login_details_for_p3_main else None
        
        # Pass the initial_access_token from the *first* login for use in variants
        test_dev_client_refresh_failure(session_problem3_main, refresh_token_for_p3_main, initial_access_token, ctx_p3)
    if OVERALL_TEST_FAILURE_FLAG and not IS_DEBUG_ENABLED: print(f"{RED}Exiting due to failure.{NC}"); sys.exit(1)

    # Test Next.js /api/auth_test endpoint
    # This needs the session from the initial successful login (session_initial_login)
    # Remote log collection is now global.
    with TestContext("Next.js App Internal Auth Test (/api/auth_test)") as ctx:
        if login_details_ok:
            test_nextjs_api_auth_test(session_initial_login, ctx)
        else:
            ctx.warning("Skipping /api/auth_test call because initial login failed.")
    if OVERALL_TEST_FAILURE_FLAG and not IS_DEBUG_ENABLED: print(f"{RED}Exiting due to failure.{NC}"); sys.exit(1)

    with TestContext("New Expired Token Refresh Flow") as ctx:
        if login_details_ok:
            # This test needs a session with valid cookies.
            # We can re-use session_initial_login as it should still be valid.
            test_dev_expired_token_refresh_flow(session_initial_login, ctx)
        else:
            ctx.warning("Skipping new expired token refresh flow test due to initial login failure.")
    if OVERALL_TEST_FAILURE_FLAG and not IS_DEBUG_ENABLED: print(f"{RED}Exiting due to failure.{NC}"); sys.exit(1)


    print(f"\n{BLUE}=== Dev Authentication Tests Finished ==={NC}")
    if PROBLEM_REPRODUCED_FLAG:
        print(f"{RED}One or more authentication problems from auth-problem.md WERE REPRODUCED against {DEV_API_URL}.{NC}")
    if OVERALL_TEST_FAILURE_FLAG:
        print(f"{RED}One or more tests FAILED. Check logs above.{NC}")
        sys.exit(1)
    elif not PROBLEM_REPRODUCED_FLAG and not OVERALL_TEST_FAILURE_FLAG:
        print(f"{GREEN}No authentication problems from auth-problem.md were reproduced against {DEV_API_URL}. All checks passed.{NC}")
        sys.exit(0)
    else: # Problems reproduced but no other failures
        sys.exit(0) # Or a different code like 2 if you want to distinguish "passed with known issues"

if __name__ == "__main__":
    main_dev_tests()
