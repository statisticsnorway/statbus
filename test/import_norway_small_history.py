#!/usr/bin/env python3
"""
Test script for importing Norway small history data through the REST API
This test replicates the functionality in test/sql/50_import_jobs_for_norway_small_history.sql
but uses the REST API instead of direct SQL connections.

Run with `./test/import_norway_small_history.sh [create|delete]` that uses venv.
  create: Set up and import Norway small history data (default)
  delete: Clean up by removing imported data and definitions
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
            f"{API_BASE_URL}/rest/rpc/login",
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
    url = f"{API_BASE_URL}{endpoint}"
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
    """Set up import definitions for Norway data"""
    log_info("Setting up import definitions...")
    
    # Check if import definitions already exist
    definitions = api_request(session, "GET", "/rest/import_definition?slug=in.(brreg_hovedenhet_2024,brreg_underenhet_2024)")
    
    # Create a dictionary of existing definitions by slug for quick lookup
    existing_definitions = {}
    if definitions:
        for definition in definitions:
            existing_definitions[definition["slug"]] = definition
            log_info(f"Found existing definition: {definition['slug']} (valid: {definition['valid']})")
    
    # First, check if data source exists or create it
    data_sources = api_request(session, "GET", "/rest/data_source?code=eq.brreg")
    data_source_id = None
    
    if data_sources and len(data_sources) > 0:
        data_source_id = data_sources[0]["id"]
        log_success("Found existing BRREG data source")
    else:
        # Create data source
        data_source = {
            "code": "brreg",
            "name": "Brønnøysundregistrene",
            "active": True,
            "custom": True
        }
        result = api_request(session, "POST", "/rest/data_source", data=data_source)
        if result:
            data_source_id = result[0]["id"] if isinstance(result, list) else result["id"]
            log_success("Created BRREG data source")
        else:
            log_error("Failed to create BRREG data source")
            return False
    
    # Get import targets
    targets = api_request(session, "GET", "/rest/import_target")
    if not targets or len(targets) == 0:
        log_error("No import targets found")
        return False
    
    # Find the legal unit target
    legal_unit_target = None
    for target in targets:
        table_name = target.get("table_name", "").lower()
        if "legal" in table_name or "lu" in table_name:
            legal_unit_target = target
            break
    
    if not legal_unit_target:
        log_error("Import target for legal units not found in available targets")
        log_info("Available targets:")
        for i, target in enumerate(targets):
            log_info(f"  {i+1}. {target.get('table_name')} (ID: {target.get('id')})")
        return False
    
    legal_unit_target_id = legal_unit_target["id"]
    log_success(f"Using import target '{legal_unit_target.get('table_name')}' (ID: {legal_unit_target_id}) for legal units")
    
    # Find the establishment target
    establishment_target = None
    for target in targets:
        table_name = target.get("table_name", "").lower()
        if "establishment" in table_name or "est" in table_name or "es" in table_name:
            establishment_target = target
            break
    
    if not establishment_target:
        log_error("Import target for establishments not found in available targets")
        log_info("Available targets:")
        for i, target in enumerate(targets):
            log_info(f"  {i+1}. {target.get('table_name')} (ID: {target.get('id')})")
        return False
    
    establishment_target_id = establishment_target["id"]
    log_success(f"Using import target '{establishment_target.get('table_name')}' (ID: {establishment_target_id}) for establishments")
    
    # Function to ensure a definition exists and is in draft mode
    def ensure_definition(slug, name, target_id):
        if slug in existing_definitions:
            definition = existing_definitions[slug]
            definition_id = definition["id"]
            log_success(f"Found existing {name} definition (ID: {definition_id})")
            
            # Set to draft mode if needed
            if not definition.get("draft", False):
                update_result = api_request(session, "PATCH", f"/rest/import_definition?id=eq.{definition_id}", 
                                          data={"draft": True, "valid": False}, expected_status=204)
                if update_result is not None:
                    log_success(f"Set existing {name} definition to draft mode")
                else:
                    log_warning(f"Failed to set existing {name} definition to draft mode")
        else:
            # Create new definition
            new_def = {
                "slug": slug,
                "name": name,
                "target_id": target_id,
                "data_source_id": data_source_id,
                "note": f"Import definition for {name}",
                "draft": True,
                "valid": False
            }
            
            result = api_request(session, "POST", "/rest/import_definition", data=new_def)
            if not result:
                log_error(f"Failed to create {name} import definition")
                return None
            
            # Extract ID from response
            if isinstance(result, list) and len(result) > 0:
                definition_id = result[0]["id"]
            elif isinstance(result, dict) and "id" in result:
                definition_id = result["id"]
            else:
                # Try to get by querying
                created_def = api_request(session, "GET", f"/rest/import_definition?slug=eq.{slug}")
                if created_def and len(created_def) > 0:
                    definition_id = created_def[0]["id"]
                else:
                    log_error(f"Could not get ID for created {name} definition")
                    return None
            
            log_success(f"Created {name} import definition with ID: {definition_id}")
        
        return definition_id
    
    # Function to ensure source columns exist
    def ensure_source_columns(definition_id, columns):
        # Get existing source columns
        existing_columns = api_request(session, "GET", f"/rest/import_source_column?definition_id=eq.{definition_id}")
        existing_col_dict = {col["column_name"]: col["id"] for col in existing_columns} if existing_columns else {}
        
        # Create any missing columns
        for i, col_info in enumerate(columns):
            col_name = col_info["column_name"]
            if col_name not in existing_col_dict:
                new_col = {
                    "definition_id": definition_id,
                    "column_name": col_name,
                    "priority": col_info["priority"]
                }
                result = api_request(session, "POST", "/rest/import_source_column", data=new_col)
                if result:
                    log_success(f"Created source column: {col_name}")
                    # Update dictionary with new ID
                    if isinstance(result, list) and len(result) > 0:
                        existing_col_dict[col_name] = result[0]["id"]
                    elif isinstance(result, dict) and "id" in result:
                        existing_col_dict[col_name] = result["id"]
                else:
                    log_warning(f"Failed to create source column: {col_name}")
        
        # If we added columns, refresh the list
        if len(existing_col_dict) < len(columns):
            updated_columns = api_request(session, "GET", f"/rest/import_source_column?definition_id=eq.{definition_id}")
            if updated_columns:
                existing_col_dict = {col["column_name"]: col["id"] for col in updated_columns}
        
        return existing_col_dict
    
    # Function to ensure mappings exist
    def ensure_mappings(definition_id, target_id, source_col_dict, mapping_pairs):
        # Get target columns
        target_columns = api_request(session, "GET", f"/rest/import_target_column?target_id=eq.{target_id}")
        if not target_columns:
            log_error(f"Could not get target columns for target_id {target_id}")
            return False
        
        # Create target column dictionary
        target_col_dict = {col["column_name"]: col["id"] for col in target_columns}
        
        # Get temporal column IDs
        valid_from_id = target_col_dict.get("valid_from")
        valid_to_id = target_col_dict.get("valid_to")
        
        if not valid_from_id or not valid_to_id:
            log_error(f"Could not find temporal column IDs for target_id {target_id}")
            log_info(f"Available target columns: {', '.join([col['column_name'] for col in target_columns])}")
            return False
        
        # Get existing mappings
        existing_mappings = api_request(session, "GET", f"/rest/import_mapping?definition_id=eq.{definition_id}")
        
        # Create a set of existing mappings for quick lookup
        existing_mapping_set = set()
        if existing_mappings:
            for mapping in existing_mappings:
                source_id = mapping.get("source_column_id")
                target_id = mapping.get("target_column_id")
                if source_id and target_id:
                    existing_mapping_set.add(f"{source_id}:{target_id}")
                elif mapping.get("source_expression") == "default" and target_id:
                    # For temporal columns with default expression
                    existing_mapping_set.add(f"default:{target_id}")
        
        # First ensure temporal columns are mapped
        temporal_mappings = [
            {"source_column_id": None,
             "target_column_id": valid_from_id,
             "source_expression": "default",
             "definition_id": definition_id},
            {"source_column_id": None,
             "target_column_id": valid_to_id,
             "source_expression": "default",
             "definition_id": definition_id}
        ]
        
        for mapping in temporal_mappings:
            target_id = mapping["target_column_id"]
            mapping_key = f"default:{target_id}"
            
            if mapping_key not in existing_mapping_set:
                result = api_request(session, "POST", "/rest/import_mapping", data=mapping)
                if result:
                    log_success(f"Created temporal mapping for column ID {target_id}")
                    existing_mapping_set.add(mapping_key)
                else:
                    # Try once more with delay
                    time.sleep(1)
                    result = api_request(session, "POST", "/rest/import_mapping", data=mapping)
                    if result:
                        log_success(f"Created temporal mapping for column ID {target_id} on retry")
                        existing_mapping_set.add(mapping_key)
                    else:
                        log_error(f"Failed to create temporal mapping for column ID {target_id}")
                        return False
        
        # Now create regular column mappings
        for source_name, target_name in mapping_pairs:
            source_id = source_col_dict.get(source_name)
            
            if not source_id:
                log_warning(f"Source column '{source_name}' not found")
                continue
                
            # Handle NULL target mappings (columns that should be ignored)
            if target_name is None:
                mapping_key = f"{source_id}:null"
                
                if mapping_key not in existing_mapping_set:
                    mapping = {
                        "definition_id": definition_id,
                        "source_column_id": source_id,
                        "target_column_id": None
                    }
                    
                    result = api_request(session, "POST", "/rest/import_mapping", data=mapping)
                    if result:
                        log_success(f"Created NULL mapping for source column: {source_name}")
                        existing_mapping_set.add(mapping_key)
                    else:
                        log_warning(f"Failed to create NULL mapping for source column: {source_name}")
            else:
                # Regular mapping with target column
                target_id = target_col_dict.get(target_name)
                
                if not target_id:
                    log_warning(f"Target column '{target_name}' not found")
                    continue
                    
                mapping_key = f"{source_id}:{target_id}"
                
                if mapping_key not in existing_mapping_set:
                    mapping = {
                        "definition_id": definition_id,
                        "source_column_id": source_id,
                        "target_column_id": target_id
                    }
                    
                    result = api_request(session, "POST", "/rest/import_mapping", data=mapping)
                    if result:
                        log_success(f"Created mapping: {source_name} -> {target_name}")
                        existing_mapping_set.add(mapping_key)
                    else:
                        log_warning(f"Failed to create mapping: {source_name} -> {target_name}")
        
        return True
    
    # Process hovedenhet (legal unit) definition
    hovedenhet_def_id = ensure_definition(
        "brreg_hovedenhet_2024", 
        "BRREG Hovedenhet 2024", 
        legal_unit_target_id
    )
    
    if not hovedenhet_def_id:
        return False
    
    # Define source columns for hovedenhet with target mappings - order is important and must match priority
    hovedenhet_columns = [
        {"column_name": "organisasjonsnummer", "priority": 1, "target_name": "tax_ident"},
        {"column_name": "navn", "priority": 2, "target_name": "name"},
        {"column_name": "organisasjonsform.kode", "priority": 3, "target_name": "legal_form_code"},
        {"column_name": "organisasjonsform.beskrivelse", "priority": 4, "target_name": None},
        {"column_name": "naeringskode1.kode", "priority": 5, "target_name": "primary_activity_category_code"},
        {"column_name": "naeringskode1.beskrivelse", "priority": 6, "target_name": None},
        {"column_name": "naeringskode2.kode", "priority": 7, "target_name": "secondary_activity_category_code"},
        {"column_name": "naeringskode2.beskrivelse", "priority": 8, "target_name": None},
        {"column_name": "naeringskode3.kode", "priority": 9, "target_name": None},
        {"column_name": "naeringskode3.beskrivelse", "priority": 10, "target_name": None},
        {"column_name": "hjelpeenhetskode.kode", "priority": 11, "target_name": None},
        {"column_name": "hjelpeenhetskode.beskrivelse", "priority": 12, "target_name": None},
        {"column_name": "harRegistrertAntallAnsatte", "priority": 13, "target_name": None},
        {"column_name": "antallAnsatte", "priority": 14, "target_name": "employees"},
        {"column_name": "registreringsdatoAntallAnsatteEnhetsregisteret", "priority": 15, "target_name": None},
        {"column_name": "registreringsdatoantallansatteNAVAaregisteret", "priority": 16, "target_name": None},
        {"column_name": "hjemmeside", "priority": 17, "target_name": "web_address"},
        {"column_name": "epostadresse", "priority": 18, "target_name": None},
        {"column_name": "telefon", "priority": 19, "target_name": None},
        {"column_name": "mobil", "priority": 20, "target_name": None},
        {"column_name": "postadresse.adresse", "priority": 21, "target_name": "postal_address_part1"},
        {"column_name": "postadresse.poststed", "priority": 22, "target_name": "postal_postplace"},
        {"column_name": "postadresse.postnummer", "priority": 23, "target_name": "postal_postcode"},
        {"column_name": "postadresse.kommune", "priority": 24, "target_name": None},
        {"column_name": "postadresse.kommunenummer", "priority": 25, "target_name": "postal_region_code"},
        {"column_name": "postadresse.land", "priority": 26, "target_name": None},
        {"column_name": "postadresse.landkode", "priority": 27, "target_name": "postal_country_iso_2"},
        {"column_name": "forretningsadresse.adresse", "priority": 28, "target_name": "physical_address_part1"},
        {"column_name": "forretningsadresse.poststed", "priority": 29, "target_name": "physical_postplace"},
        {"column_name": "forretningsadresse.postnummer", "priority": 30, "target_name": "physical_postcode"},
        {"column_name": "forretningsadresse.kommune", "priority": 31, "target_name": None},
        {"column_name": "forretningsadresse.kommunenummer", "priority": 32, "target_name": "physical_region_code"},
        {"column_name": "forretningsadresse.land", "priority": 33, "target_name": None},
        {"column_name": "forretningsadresse.landkode", "priority": 34, "target_name": "physical_country_iso_2"},
        {"column_name": "institusjonellSektorkode.kode", "priority": 35, "target_name": "sector_code"},
        {"column_name": "institusjonellSektorkode.beskrivelse", "priority": 36, "target_name": None},
        {"column_name": "sisteInnsendteAarsregnskap", "priority": 37, "target_name": None},
        {"column_name": "registreringsdatoenhetsregisteret", "priority": 38, "target_name": None},
        {"column_name": "stiftelsesdato", "priority": 39, "target_name": "birth_date"},
        {"column_name": "registrertIMvaRegisteret", "priority": 40, "target_name": None},
        {"column_name": "registreringsdatoMerverdiavgiftsregisteret", "priority": 41, "target_name": None},
        {"column_name": "registreringsdatoMerverdiavgiftsregisteretEnhetsregisteret", "priority": 42, "target_name": None},
        {"column_name": "frivilligMvaRegistrertBeskrivelser", "priority": 43, "target_name": None},
        {"column_name": "registreringsdatoFrivilligMerverdiavgiftsregisteret", "priority": 44, "target_name": None},
        {"column_name": "registrertIFrivillighetsregisteret", "priority": 45, "target_name": None},
        {"column_name": "registreringsdatoFrivillighetsregisteret", "priority": 46, "target_name": None},
        {"column_name": "registrertIForetaksregisteret", "priority": 47, "target_name": None},
        {"column_name": "registreringsdatoForetaksregisteret", "priority": 48, "target_name": None},
        {"column_name": "registrertIStiftelsesregisteret", "priority": 49, "target_name": None},
        {"column_name": "registrertIPartiregisteret", "priority": 50, "target_name": None},
        {"column_name": "registreringsdatoPartiregisteret", "priority": 51, "target_name": None},
        {"column_name": "konkurs", "priority": 52, "target_name": None},
        {"column_name": "konkursdato", "priority": 53, "target_name": None},
        {"column_name": "underAvvikling", "priority": 54, "target_name": None},
        {"column_name": "underAvviklingDato", "priority": 55, "target_name": None},
        {"column_name": "underTvangsavviklingEllerTvangsopplosning", "priority": 56, "target_name": None},
        {"column_name": "tvangsopplostPgaManglendeDagligLederDato", "priority": 57, "target_name": None},
        {"column_name": "tvangsopplostPgaManglendeRevisorDato", "priority": 58, "target_name": None},
        {"column_name": "tvangsopplostPgaManglendeRegnskapDato", "priority": 59, "target_name": None},
        {"column_name": "tvangsopplostPgaMangelfulltStyreDato", "priority": 60, "target_name": None},
        {"column_name": "tvangsavvikletPgaManglendeSlettingDato", "priority": 61, "target_name": None},
        {"column_name": "overordnetEnhet", "priority": 62, "target_name": None},
        {"column_name": "nedleggelsesdato", "priority": 63, "target_name": "death_date"},
        {"column_name": "maalform", "priority": 64, "target_name": None},
        {"column_name": "vedtektsdato", "priority": 65, "target_name": None},
        {"column_name": "vedtektsfestetFormaal", "priority": 66, "target_name": None},
        {"column_name": "aktivitet", "priority": 67, "target_name": None},
        {"column_name": "registreringsnummerIHjemlandet", "priority": 68, "target_name": None},
        {"column_name": "paategninger", "priority": 69, "target_name": None}
    ]
    
    # Create source columns first
    hovedenhet_source_cols = ensure_source_columns(hovedenhet_def_id, hovedenhet_columns)
    
    # Extract mapping pairs from the combined structure
    hovedenhet_mapping_pairs = [
        (col["column_name"], col["target_name"]) 
        for col in hovedenhet_columns
    ]
    
    if not ensure_mappings(hovedenhet_def_id, legal_unit_target_id, hovedenhet_source_cols, hovedenhet_mapping_pairs):
        return False
    
    # Set hovedenhet definition to valid
    update_result = api_request(session, "PATCH", f"/rest/import_definition?id=eq.{hovedenhet_def_id}", 
                              data={"draft": False, "valid": True})
    if update_result is not None:
        log_success("Set hovedenhet definition to valid")
    else:
        log_warning("Failed to set hovedenhet definition to valid")
    
    # Process underenhet (establishment) definition
    underenhet_def_id = ensure_definition(
        "brreg_underenhet_2024", 
        "BRREG Underenhet 2024", 
        establishment_target_id
    )
    
    if not underenhet_def_id:
        return False
    
    # Define source columns for underenhet with target mappings - order is important and must match priority
    underenhet_columns = [
        {"column_name": "organisasjonsnummer", "priority": 1, "target_name": "tax_ident"},
        {"column_name": "navn", "priority": 2, "target_name": "name"},
        {"column_name": "organisasjonsform.kode", "priority": 3, "target_name": None},
        {"column_name": "organisasjonsform.beskrivelse", "priority": 4, "target_name": None},
        {"column_name": "naeringskode1.kode", "priority": 5, "target_name": "primary_activity_category_code"},
        {"column_name": "naeringskode1.beskrivelse", "priority": 6, "target_name": None},
        {"column_name": "naeringskode2.kode", "priority": 7, "target_name": "secondary_activity_category_code"},
        {"column_name": "naeringskode2.beskrivelse", "priority": 8, "target_name": None},
        {"column_name": "naeringskode3.kode", "priority": 9, "target_name": None},
        {"column_name": "naeringskode3.beskrivelse", "priority": 10, "target_name": None},
        {"column_name": "hjelpeenhetskode.kode", "priority": 11, "target_name": None},
        {"column_name": "hjelpeenhetskode.beskrivelse", "priority": 12, "target_name": None},
        {"column_name": "harRegistrertAntallAnsatte", "priority": 13, "target_name": None},
        {"column_name": "antallAnsatte", "priority": 14, "target_name": "employees"},
        {"column_name": "hjemmeside", "priority": 15, "target_name": "web_address"},
        {"column_name": "postadresse.adresse", "priority": 16, "target_name": "postal_address_part1"},
        {"column_name": "postadresse.poststed", "priority": 17, "target_name": "postal_postplace"},
        {"column_name": "postadresse.postnummer", "priority": 18, "target_name": "postal_postcode"},
        {"column_name": "postadresse.kommune", "priority": 19, "target_name": None},
        {"column_name": "postadresse.kommunenummer", "priority": 20, "target_name": "postal_region_code"},
        {"column_name": "postadresse.land", "priority": 21, "target_name": None},
        {"column_name": "postadresse.landkode", "priority": 22, "target_name": "postal_country_iso_2"},
        {"column_name": "beliggenhetsadresse.adresse", "priority": 23, "target_name": "physical_address_part1"},
        {"column_name": "beliggenhetsadresse.poststed", "priority": 24, "target_name": "physical_postplace"},
        {"column_name": "beliggenhetsadresse.postnummer", "priority": 25, "target_name": "physical_postcode"},
        {"column_name": "beliggenhetsadresse.kommune", "priority": 26, "target_name": None},
        {"column_name": "beliggenhetsadresse.kommunenummer", "priority": 27, "target_name": "physical_region_code"},
        {"column_name": "beliggenhetsadresse.land", "priority": 28, "target_name": None},
        {"column_name": "beliggenhetsadresse.landkode", "priority": 29, "target_name": "physical_country_iso_2"},
        {"column_name": "registreringsdatoIEnhetsregisteret", "priority": 30, "target_name": None},
        {"column_name": "frivilligMvaRegistrertBeskrivelser", "priority": 31, "target_name": None},
        {"column_name": "registrertIMvaregisteret", "priority": 32, "target_name": None},
        {"column_name": "oppstartsdato", "priority": 33, "target_name": "birth_date"},
        {"column_name": "datoEierskifte", "priority": 34, "target_name": None},
        {"column_name": "overordnetEnhet", "priority": 35, "target_name": "legal_unit_tax_ident"},
        {"column_name": "nedleggelsesdato", "priority": 36, "target_name": "death_date"}
    ]
    
    # Create source columns first
    underenhet_source_cols = ensure_source_columns(underenhet_def_id, underenhet_columns)
    
    # Extract mapping pairs from the combined structure
    underenhet_mapping_pairs = [
        (col["column_name"], col["target_name"]) 
        for col in underenhet_columns
    ]
    
    if not ensure_mappings(underenhet_def_id, establishment_target_id, underenhet_source_cols, underenhet_mapping_pairs):
        return False
    
    # Set underenhet definition to valid
    update_result = api_request(session, "PATCH", f"/rest/import_definition?id=eq.{underenhet_def_id}", 
                              data={"draft": False, "valid": True})
    if update_result is not None:
        log_success("Set underenhet definition to valid")
    else:
        log_warning("Failed to set underenhet definition to valid")
    
    # Verify import definitions are valid
    definitions = api_request(session, "GET", "/rest/import_definition?slug=in.(brreg_hovedenhet_2024,brreg_underenhet_2024)")
    
    if definitions and len(definitions) == 2 and all(d.get("valid") for d in definitions):
        log_success("Import definitions created and validated successfully")
        return True
    else:
        log_warning("Import definitions may not be fully valid")
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
        
        # Debug the target table structure to help diagnose issues
        debug_info(f"Getting target table structure for underenhet definition (ID: {underenhet_def_id})")
        target_info = api_request(session, "GET", f"/rest/import_target?id=eq.{2}")
        if target_info:
            debug_info(f"Target table info: {json.dumps(target_info, indent=2)}")
        
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
            upload_url = f"{API_BASE_URL}/rest/{upload_table_name}"
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
    
    Connects to /api/sse/worker-check SSE endpoint and monitors the worker status
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
            sse_url = f"{API_BASE_URL}/api/sse/worker-check"
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
            
            # Process SSE events
            buffer = ""
            for line in sse_response.iter_lines():
                if stop_event.is_set():
                    break
                
                if not line:
                    # Empty line marks the end of an event
                    if buffer:
                        # Process the complete event
                        event_parts = buffer.split("\n")
                        event_type = None
                        event_data = None
                        
                        for part in event_parts:
                            if part.startswith("event: "):
                                event_type = part[7:]
                            elif part.startswith("data: "):
                                event_data = part[6:]
                        
                        if event_type and event_data:
                            event_queue.put(("event", {"type": event_type, "data": event_data}))
                        
                        buffer = ""
                    continue
                
                # Add line to buffer
                buffer += line.decode('utf-8') + "\n"
            
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
                
                elif event_type == "event":
                    # Handle check events
                    if event_data["type"] == "check":
                        try:
                            # Parse the payload as JSON
                            payload = json.loads(event_data["data"])
                            
                            # Update derivation status
                            if "isDerivingUnits" in payload:
                                old_status = derivation_status["isDerivingUnits"]
                                derivation_status["isDerivingUnits"] = payload["isDerivingUnits"]
                                if old_status != derivation_status["isDerivingUnits"]:
                                    log_info(f"Deriving units status changed: {old_status} -> {derivation_status['isDerivingUnits']}")
                            
                            if "isDerivingReports" in payload:
                                old_status = derivation_status["isDerivingReports"]
                                derivation_status["isDerivingReports"] = payload["isDerivingReports"]
                                if old_status != derivation_status["isDerivingReports"]:
                                    log_info(f"Deriving reports status changed: {old_status} -> {derivation_status['isDerivingReports']}")
                            
                            # Check if all derivation is completed
                            if check_all_completed():
                                log_success("Worker has finished all derivation tasks (detected by SSE)")
                                all_completed = True
                                break
                        except json.JSONDecodeError:
                            log_warning(f"Failed to parse check event data: {event_data['data']}")
                    
                    # Handle connected event
                    elif event_data["type"] == "connected":
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
    manage_script_path = WORKSPACE / "devops" / "manage-statbus.sh"
    
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
    return parser.parse_args()

def main():
    """Main test sequence"""
    # Parse command line arguments
    args = parse_args()
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
        response = requests.get(f"{API_BASE_URL}/rest/rpc/auth_status", timeout=5)
        log_info(f"Server is reachable. Status: {response.status_code}")
    except requests.RequestException as e:
        log_error(f"Server is not reachable at {API_BASE_URL}: {e}", 
                 lambda: print(f"{RED}Please check if the server is running and the CADDY_HTTP_BIND_ADDRESS environment variable is correct.{NC}"))
        return
    
    # Login as admin
    admin_id = api_login(session, ADMIN_EMAIL, ADMIN_PASSWORD)
    if not admin_id:
        log_error(f"Admin login failed for {ADMIN_EMAIL}, cannot proceed with tests", 
                 lambda: print(f"{RED}Please verify the admin credentials and server configuration.{NC}"))
        return
    
    if action == "create":
        # Create test users first (only for 'create' action)
        if not create_test_users():
            log_warning("Failed to create test users, proceeding anyway...")
            # Don't exit, maybe they already exist
            
        # Run Norway setup if needed
        log_info("Setting up Statbus for Norway...")
        try:
            # Check if Norway setup is already done by checking for activity categories
            categories = api_request(session, "GET", "/rest/activity_category_available_custom?limit=1")
            
            if categories and len(categories) > 0:
                log_success("Norway setup already completed")
            else:
                log_info("Performing Norway setup steps...")
                
                # Step 1: Set activity category standard to NACE v2.1
                # First get the activity_category_standard ID for NACE v2.1
                standards = api_request(session, "GET", "/rest/activity_category_standard?code=eq.nace_v2.1")
                if not standards or len(standards) == 0:
                    log_error("NACE v2.1 standard not found")
                    return
                
                nace_id = standards[0]["id"]
                
                # Update settings to use this standard
                settings_update = {
                    "activity_category_standard_id": nace_id,
                    "only_one_setting": True
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
                    return
                
                with open(activity_file, 'rb') as f:
                    files = {'file': (activity_file.name, f, 'text/csv')}
                    
                    # Use the REST endpoint for direct batch insert of activity categories
                    with open(activity_file, 'r') as f:
                        csv_content = f.read()
                    
                    response = session.post(
                        f"{API_BASE_URL}/rest/activity_category_available_custom",
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code == 200:
                        log_success("Uploaded activity categories successfully")
                    else:
                        log_warning(f"Failed to upload activity categories: {response.status_code} - {response.text}")
                
                # Step 3: Import regions
                log_info("Importing regions...")
                regions_file = WORKSPACE / "samples" / "norway" / "regions" / "norway-regions-2024.csv"
                
                if not regions_file.exists():
                    log_error(f"Regions file not found: {regions_file}")
                    return
                
                with open(regions_file, 'r') as f:
                    csv_content = f.read()
                    
                    # Use the REST endpoint for direct batch insert of regions
                    response = session.post(
                        f"{API_BASE_URL}/rest/region_upload",
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code == 200:
                        log_success("Uploaded regions successfully")
                    else:
                        log_warning(f"Failed to upload regions: {response.status_code} - {response.text}")
                
                # Step 4: Import sectors
                log_info("Importing sectors...")
                sectors_file = WORKSPACE / "samples" / "norway" / "sector" / "sector_norway.csv"
                
                if not sectors_file.exists():
                    log_error(f"Sectors file not found: {sectors_file}")
                    return
                
                with open(sectors_file, 'r') as f:
                    csv_content = f.read()
                    
                    # Use the REST endpoint for direct batch insert of sectors
                    response = session.post(
                        f"{API_BASE_URL}/rest/sector_custom_only",
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code == 200:
                        log_success("Uploaded sectors successfully")
                    else:
                        log_warning(f"Failed to upload sectors: {response.status_code} - {response.text}")
                
                # Step 5: Import legal forms
                log_info("Importing legal forms...")
                legal_forms_file = WORKSPACE / "samples" / "norway" / "legal_form" / "legal_form_norway.csv"
                
                if not legal_forms_file.exists():
                    log_error(f"Legal forms file not found: {legal_forms_file}")
                    return
                
                with open(legal_forms_file, 'r') as f:
                    csv_content = f.read()
                    
                    # Use the REST endpoint for direct batch insert of legal forms
                    response = session.post(
                        f"{API_BASE_URL}/rest/legal_form_custom_only",
                        headers={"Content-Type": "text/csv"},
                        data=csv_content
                    )
                    
                    if response.status_code == 200:
                        log_success("Uploaded legal forms successfully")
                    else:
                        log_warning(f"Failed to upload legal forms: {response.status_code} - {response.text}")
                
                # Verify setup was completed
                categories = api_request(session, "GET", "/rest/activity_category_available_custom?limit=1")
                if categories and len(categories) > 0:
                    log_success("Norway setup completed successfully")
                else:
                    log_warning("Norway setup may not have completed successfully")
        except Exception as e:
            log_warning(f"Error during Norway setup: {e}")
        
        # Setup import definitions
        if not setup_import_definitions(session):
            log_error("Failed to set up import definitions")
            return
        
        # Create import jobs
        if not create_import_jobs(session):
            log_error("Failed to create import jobs")
            return
        
        # Upload data files
        if not upload_data_files(session):
            log_error("Failed to upload data files")
            return
        
        # Wait for background processing of import jobs
        if not wait_for_worker_processing_of_import_jobs(session):
            log_error("Failed to process import jobs")
            return
        
        # Wait for worker to finish deriving statistical units and reports
        if not wait_for_worker_derive(session):
            log_warning("Failed to wait for worker derivation to complete")
            # Continue anyway as this is not critical
        
        # Verify imported data
        if not verify_imported_data(session):
            log_error("Failed to verify imported data")
            return
        
        # Print summary
        print(f"\n{GREEN}=== Norway Small History Import Test Completed Successfully ==={NC}\n")
    
    elif action == "delete":
        # Delete imported data
        if not delete_imported_data(session):
            log_error("Failed to delete imported data")
            return
        
        # Print summary
        print(f"\n{GREEN}=== Norway Small History Cleanup Completed Successfully ==={NC}\n")

if __name__ == "__main__":
    # If no arguments provided, show usage
    if len(sys.argv) < 2:
        print(f"{RED}Error: Missing required parameter (create or delete){NC}")
        print(f"Usage: {sys.argv[0]} [create|delete]")
        print(f"  create: Set up and import Norway small history data")
        print(f"  delete: Clean up by removing imported data and definitions")
        sys.exit(1)
    
    # Validate action parameter
    action = sys.argv[1].lower()
    if action not in ["create", "delete"]:
        print(f"{RED}Error: Invalid parameter. Must be 'create' or 'delete'{NC}")
        print(f"Usage: {sys.argv[0]} [create|delete]")
        sys.exit(1)
    
    main()
