#!/bin/bash

# Caddy L4 Proxy Test Script
# Tests PostgreSQL connections through Caddy proxy with SSL/TLS routing
# Records docker compose logs for each test case

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PGUSER=statbus_speed
PGPASSWORD=dhhlSam1dMlh9s2aBN2b
LOG_FILE="test-caddy-l4-results-$(date +%Y%m%d-%H%M%S).log"
TIMEOUT=5

# Function to print section headers
print_header() {
    echo ""
    echo "========================================" | tee -a "$LOG_FILE"
    echo "$1" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Function to print test name
print_test() {
    echo -e "${BLUE}TEST: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to print command
print_command() {
    echo -e "${YELLOW}Command:${NC} $1" | tee -a "$LOG_FILE"
}

# Function to get current timestamp in RFC3339 format
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Function to extract logs since timestamp
extract_logs() {
    local timestamp=$1
    local test_name=$2

    echo "" | tee -a "$LOG_FILE"
    echo "Proxy logs for: $test_name" | tee -a "$LOG_FILE"
    echo "---" | tee -a "$LOG_FILE"

    if [ -n "$timestamp" ]; then
        docker compose logs --since "$timestamp" proxy 2>/dev/null | tee -a "$LOG_FILE"
        # Check if we got any logs
        local log_count=$(docker compose logs --since "$timestamp" proxy 2>/dev/null | wc -l)
        if [ "$log_count" -eq 0 ]; then
            echo "(No new logs since $timestamp)" | tee -a "$LOG_FILE"
        fi
    else
        echo "(No timestamp available, showing last 10 lines)" | tee -a "$LOG_FILE"
        docker compose logs -n 10 proxy 2>/dev/null | tee -a "$LOG_FILE"
    fi

    echo "---" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Function to run test with timeout and log extraction
run_test() {
    local test_name=$1
    local command=$2
    local expected_result=$3

    print_test "$test_name"
    print_command "$command"

    # Get timestamp before running command
    local before_timestamp=$(get_current_timestamp)
    echo "Timestamp before test: $before_timestamp" | tee -a "$LOG_FILE"

    # Run command with timeout
    echo -e "${YELLOW}Running...${NC}"
    set +e
    timeout $TIMEOUT bash -c "$command" > /tmp/test_output.txt 2>&1
    local exit_code=$?
    set -e

    # Determine result
    local result=""
    if [ $exit_code -eq 0 ]; then
        result="${GREEN}SUCCESS${NC}"
        echo -e "Result: $result" | tee -a "$LOG_FILE"
    elif [ $exit_code -eq 124 ]; then
        result="${RED}TIMEOUT${NC}"
        echo -e "Result: $result (command timed out after ${TIMEOUT}s)" | tee -a "$LOG_FILE"
    else
        result="${RED}FAILED${NC}"
        echo -e "Result: $result (exit code: $exit_code)" | tee -a "$LOG_FILE"
    fi

    # Show output
    if [ -s /tmp/test_output.txt ]; then
        echo "" | tee -a "$LOG_FILE"
        echo "Output:" | tee -a "$LOG_FILE"
        cat /tmp/test_output.txt | tee -a "$LOG_FILE"
    fi

    # Extract and display logs
    sleep 1  # Give logs a moment to flush
    extract_logs "$before_timestamp" "$test_name"

    echo -e "Expected: $expected_result" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Main script
print_header "Caddy L4 Proxy Test Suite - $(date)"

echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Timeout per test: ${TIMEOUT}s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check if docker compose is running
if ! docker compose ps proxy >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker compose proxy service is not running${NC}" | tee -a "$LOG_FILE"
    echo "Please start it with: docker compose up -d proxy" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "${GREEN}Docker compose proxy service is running${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Test 1: Cleartext psql against port 3020 (should work)
run_test \
    "Test 1: Cleartext psql against port 3020" \
    "PGHOST=127.0.0.1 PGPORT=3020 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "Should work - cleartext connection to port 3020"

# Test 2: Cleartext psql against port 3021 (should fail - SSL only)
run_test \
    "Test 2: Cleartext psql against port 3021" \
    "PGHOST=127.0.0.1 PGPORT=3021 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "Should fail - port 3021 requires SSL"

# Test 3: Cleartext psql against port 3024 (should work)
run_test \
    "Test 3: Cleartext psql against port 3024" \
    "PGHOST=127.0.0.1 PGPORT=3024 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "Should work - cleartext connection to port 3024"

# Test 4: SSL psql against port 3021 with local.statbus.org
run_test \
    "Test 4: SSL psql against port 3021 (local.statbus.org)" \
    "PGSSLNEGOTIATION=direct PGSSLMODE=require PGSSLSNI=1 PGHOST=local.statbus.org PGPORT=3021 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "Should work - SSL connection with correct SNI"

# Test 5: SSL psql against port 3024 with local.statbus.org
run_test \
    "Test 5: SSL psql against port 3024 (local.statbus.org)" \
    "PGSSLNEGOTIATION=direct PGSSLMODE=require PGSSLSNI=1 PGHOST=local.statbus.org PGPORT=3024 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "Should work - SSL connection with correct SNI"

# Test 6: SSL psql against port 3021 with localhost (SNI mismatch)
run_test \
    "Test 6: SSL psql against port 3021 (localhost - SNI mismatch)" \
    "PGSSLNEGOTIATION=direct PGSSLMODE=require PGSSLSNI=1 PGHOST=localhost PGPORT=3021 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "Behavior depends on Caddy config - may fail or fallback"

# Test 7: SSL psql against port 3021 with 127.0.0.1 (no SNI)
run_test \
    "Test 7: SSL psql against port 3021 (127.0.0.1 - no SNI)" \
    "PGSSLNEGOTIATION=direct PGSSLMODE=require PGHOST=127.0.0.1 PGPORT=3021 PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD psql -c 'SELECT 1;' -t" \
    "May fail if Caddy requires SNI for routing"

# Summary
print_header "Test Summary"
echo "All tests completed. Results saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "To view full logs:" | tee -a "$LOG_FILE"
echo "  cat $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "To view just the proxy logs:" | tee -a "$LOG_FILE"
echo "  docker compose logs proxy" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Cleanup
rm -f /tmp/test_output.txt

echo -e "${GREEN}Testing complete!${NC}"
