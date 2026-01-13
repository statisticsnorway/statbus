# Caddy L4 Proxy Test Script

This script tests PostgreSQL connections through a Caddy Layer 4 proxy with SSL/TLS routing capabilities. It records docker compose logs for each test case to help diagnose connection issues.

## Prerequisites

- Docker and Docker Compose running
- PostgreSQL accessible through Caddy proxy
- `psql` client installed
- Caddy proxy service running (container name should contain "proxy")

## Usage

### Basic Usage

```bash
./test-caddy-l4.sh
```

The script will:
1. Run a series of PostgreSQL connection tests
2. Display results in color-coded format
3. Capture and display relevant Caddy proxy logs for each test
4. Save all output to a timestamped log file

### What Gets Tested

1. **Port 3020 - Cleartext Connection** (Expected: SUCCESS)
   - Tests basic PostgreSQL connection without SSL

2. **Port 3021 - Cleartext Connection** (Expected: FAIL)
   - Verifies that port 3021 rejects non-SSL connections

3. **Port 3024 - Cleartext Connection** (Expected: SUCCESS)
   - Tests another cleartext endpoint

4. **Port 3021 - SSL with dev.statbus.org** (Expected: SUCCESS)
   - Tests SSL connection with proper SNI (Server Name Indication)

5. **Port 3024 - SSL with dev.statbus.org** (Expected: SUCCESS)
   - Tests SSL connection on alternate port with SNI

6. **Port 3021 - SSL with localhost** (Expected: VARIES)
   - Tests SSL with SNI mismatch (localhost vs dev.statbus.org)

7. **Port 3021 - SSL with 127.0.0.1** (Expected: VARIES)
   - Tests SSL without SNI (IP address doesn't send SNI)

## Output

The script creates a timestamped log file: `test-caddy-l4-results-YYYYMMDD-HHMMSS.log`

Each test includes:
- Test description
- Exact command run
- Test result (SUCCESS/FAILED/TIMEOUT)
- Command output
- Relevant Caddy proxy logs captured during the test
- Expected behavior

### Result Codes

- **SUCCESS** (Green): Connection succeeded
- **FAILED** (Red): Connection failed with error
- **TIMEOUT** (Red): Connection hung and timed out (default 5 seconds)

## Configuration

You can modify these variables at the top of the script:

```bash
PGUSER=statbus_speed           # PostgreSQL username
PGPASSWORD=dhhlSam1dMlh9s2aBN2b # PostgreSQL password
TIMEOUT=5                       # Timeout in seconds per test
```

## Understanding the Results

### Cleartext Tests (Ports 3020, 3024)
These should connect successfully without SSL. If they fail, check:
- Is PostgreSQL accessible?
- Is the Caddy proxy routing correctly?
- Check proxy logs for connection errors

### SSL Tests (Port 3021)
These use PostgreSQL's direct SSL negotiation. The behavior depends on:
- **SNI Routing**: Caddy can route based on the hostname in the SSL handshake
- **Host Header**: Using `PGHOST=dev.statbus.org` sends the correct SNI
- **IP Address**: Using `PGHOST=127.0.0.1` doesn't send SNI

### Common Issues

**Hangs/Timeouts on SSL connections:**
- SSL handshake not completing
- Caddy not properly terminating or routing SSL
- Check Caddy Layer 4 configuration for TLS settings

**Cleartext fails on port 3021:**
- Expected behavior if port requires SSL
- Verify Caddy is configured to reject non-SSL on this port

**All tests fail:**
- Check if Docker Compose services are running
- Verify PostgreSQL is accessible
- Review Caddy configuration

## Analyzing Logs

The captured proxy logs show:
- Connection attempts
- SSL handshake details
- Routing decisions
- Errors and warnings

Look for entries containing:
- `"level":"error"` - Connection errors
- `"level":"warn"` - Warnings about SSL or routing
- Connection/disconnection events
- TLS handshake messages

## Manual Log Inspection

To view all proxy logs:
```bash
docker compose logs proxy
```

To view logs since a specific time:
```bash
docker compose logs --since '2025-11-27T13:06:06Z' proxy
```

To follow logs in real-time:
```bash
docker compose logs -f proxy
```

## Troubleshooting

### Script says "proxy service is not running"
```bash
docker compose up -d proxy
```

### Want more detailed output
Increase the log capture by modifying the `extract_logs` function or run:
```bash
docker compose logs proxy > full-proxy-logs.txt
```

### Tests timing out
Increase the `TIMEOUT` variable at the top of the script:
```bash
TIMEOUT=10  # 10 seconds
```

### Need to test with different credentials
Edit the script and change:
```bash
PGUSER=your_username
PGPASSWORD=your_password
```

## Example Output

```
========================================
Caddy L4 Proxy Test Suite - 2025-01-27 14:30:00
========================================

Log file: test-caddy-l4-results-20250127-143000.log
Timeout per test: 5s

TEST: Test 1: Cleartext psql against port 3020
Command: PGHOST=127.0.0.1 PGPORT=3020 PGUSER=statbus_speed PGPASSWORD=*** psql -c 'SELECT 1;' -t
Running...
Result: SUCCESS

Proxy logs for: Test 1: Cleartext psql against port 3020
---
{"level":"info","ts":1764248766.442194,"msg":"new connection","remote":"127.0.0.1:52341"}
---

Expected: Should work - cleartext connection to port 3020
```

## Related Files

- `docker-compose.yml` - Docker Compose configuration
- Caddy configuration (likely in `Caddyfile` or `caddy.json`)
- PostgreSQL configuration

## Support

For issues or questions about:
- **This script**: Check the inline comments and modify as needed
- **Caddy configuration**: Review Caddy Layer 4 documentation
- **PostgreSQL SSL**: Review PostgreSQL SSL/TLS documentation