# StatBus Integration Guide

**Level up from the web interface to API integration and direct database access.**

This guide covers **Level 2** (REST API) and **Level 3** (Direct PostgreSQL) of StatBus's progressive architecture. If you're comfortable with the web interface (Level 1) and ready for more power, you're in the right place.

## The StatBus 1-2-3 Architecture

**You've been using Level 1** - the web interface with IMPORT, VIEW/SEARCH, and REPORT actions. That covers 80% of use cases for most users.

**Ready for Level 2?** - Copy those `/rest` calls from your browser's network inspector into scripts (Python, R, JavaScript). Same data, same security, but now automated and integrated with your other tools.

**Need Level 3?** - Connect directly to PostgreSQL with psql, pgAdmin, DBeaver, or database drivers in your programming language. Full SQL capabilities, still the same security (Row Level Security enforced at the database level).

### Why This Matters

Unlike traditional statistical software that locks you into one interface, StatBus lets you **progressively disclose** complexity:
- Start simple with the web
- Upgrade to REST scripting when you need automation
- Graduate to direct database access when you need SQL power

**The key**: Security is in the database (PostgreSQL Row Level Security), not in a backend API layer. This means:
- ✅ Same security regardless of how you connect
- ✅ Each user is a PostgreSQL role with the same password everywhere
- ✅ No backend abstraction limiting what you can do
- ✅ Type-safe integrations (TypeScript types generated directly from database schema)

---

## Quick Start

Choose where you want to go:

- **[Level 2: REST API](#rest-api-level-2)** - Scripting and automation (Python, R, JavaScript)
- **[Level 3: PostgreSQL Direct Access](#postgresql-direct-access-level-3)** - Full SQL power for analysis and bulk operations

---

## REST API (Level 2)

**The bridge between web and database** - Use the same `/rest` endpoints the web interface uses, but in your own scripts and applications.

### Why Use the REST API?

- **Automation**: Run reports on a schedule
- **Integration**: Connect StatBus data to other systems
- **Scripting**: Batch operations, data transformations
- **Type Safety**: Auto-generated TypeScript types from database schema

### How It Works

When you use the StatBus web interface, every action calls a `/rest` endpoint (open your browser's Network Inspector to see them). These endpoints are provided by PostgREST, which automatically generates a REST API from the PostgreSQL database schema.

**You can copy those exact same calls** into your scripts. Add an API key for authentication, and you have the same access as the web interface - with the same security (PostgreSQL Row Level Security still enforces what you can see and do).

This section helps you integrate with the StatBus REST API using Python or R.

### Getting Your API Key

1. Log into your StatBus instance using a web browser
2. Visit the API key endpoint: `https://your-statbus-url/rest/api_key?select=token`
3. Copy the token value displayed

### Setting Up Your Environment

Both Python and R examples use a `.env` file to store configuration. This file should be created in the same directory as your scripts.

Create a `.env` file with the following content:

```bash
API_URL=https://your-statbus-url
API_KEY=your-api-key-here
```

**Important:** 
- Replace `https://your-statbus-url` with your actual StatBus instance URL (e.g., `https://dev.statbus.org`)
- Replace `your-api-key-here` with the token you copied from the API key endpoint
- Never commit the `.env` file to version control (it should be in `.gitignore`)

### Quick Start

Choose your preferred language:

#### Python
```bash
cd python/
./setup.sh
source .venv/bin/activate  # Activate the virtual environment
python example.py
```

See [python/README.md](python/README.md) for detailed Python instructions.

#### R
```bash
cd r/
./setup.sh
Rscript example.r
```

See [r/README.md](r/README.md) for detailed R instructions.

### What the Setup Scripts Do

Both `setup.sh` scripts will:
1. Check if required tools (Python/R) are installed
2. Create a `.env` file template if it doesn't exist
3. Install necessary packages/libraries
4. Test the API connection using your credentials
5. Confirm everything is working correctly

After running the setup script successfully, you can run the example scripts to fetch and visualize data from StatBus.

---

## PostgreSQL Direct Access (Level 3)

**The full power of SQL** - Connect directly to the PostgreSQL database with no backend abstraction layer.

### Why Use Direct PostgreSQL Access?

- **Full SQL capabilities**: Complex joins, window functions, CTEs, custom queries
- **Familiar tools**: Use psql, pgAdmin, DBeaver, or whatever you're comfortable with
- **Bulk operations**: Large data imports, updates, and analysis
- **Deep integration**: Connect from R, Python, Node.js, or any language with a PostgreSQL driver
- **Same security**: Row Level Security still enforces access - you can only see/modify what your role allows

### How It Works

Unlike traditional web applications where the database is hidden behind an API layer, StatBus **exposes the database directly**. This is safe because:

1. **Security is in the database** - PostgreSQL Row Level Security (RLS) enforces access control
2. **Each user is a PostgreSQL role** - Same username/password as web interface
3. **RLS applies to all connections** - Whether you connect via web, REST, or psql, RLS rules are enforced

This means you can use SQL tools and database clients just like you would with any PostgreSQL database, while maintaining the same security boundaries as the web interface.

StatBus provides secure TLS-encrypted direct PostgreSQL access with SNI-based routing for multi-tenant deployments. This allows you to use familiar tools like `psql`, pgAdmin, DBeaver, or programming language database drivers.

### Prerequisites

- **PostgreSQL 17+ client** with direct TLS negotiation support
- Your StatBus username and password
- Your StatBus instance domain

### Quick Connection (psql)

Use environment variables to connect securely without exposing passwords:

```bash
# Set connection parameters (replace with your values)
export PGHOST=your-statbus-domain.com   # Your StatBus domain
export PGPORT=5432                      # Standard PostgreSQL port  
export PGDATABASE=statbus               # Database name (usually 'statbus')
export PGUSER=your_username             # Your StatBus username
export PGPASSWORD=your_password         # Your password

# TLS/SNI configuration (required for StatBus)
export PGSSLNEGOTIATION=direct          # Use modern direct TLS
export PGSSLMODE=verify-full            # Full certificate verification
export PGSSLSNI=1                       # Send hostname as SNI for routing

# Connect
psql
```

**One-liner** (less secure - password visible in command history):
```bash
PGHOST=your-statbus-domain.com PGPORT=5432 PGDATABASE=statbus PGUSER=yourname PGPASSWORD=yourpass PGSSLNEGOTIATION=direct PGSSLMODE=verify-full PGSSLSNI=1 psql
```

**Interactive password prompt** (most secure):
```bash
# Set all parameters except password
export PGHOST=your-statbus-domain.com
export PGPORT=5432
export PGDATABASE=statbus
export PGUSER=your_username
export PGSSLNEGOTIATION=direct
export PGSSLMODE=verify-full
export PGSSLSNI=1

# Connect - will prompt for password
psql
```

### Programming Language Examples

#### Python (psycopg2/psycopg3)

```python
import psycopg2

# Using connection parameters
conn = psycopg2.connect(
    host="your-statbus-domain.com",
    port=5432,
    dbname="statbus",
    user="your_username",
    password="your_password",
    sslmode="verify-full",
    # Note: psycopg2/3 doesn't support sslnegotiation parameter
    # Use PostgreSQL 17+ client libraries or set environment variables
)

# Using connection string
conn = psycopg2.connect(
    "postgresql://your_username:your_password@your-statbus-domain.com:5432/statbus?sslmode=verify-full"
)

# Using environment variables (recommended)
import os
os.environ['PGSSLNEGOTIATION'] = 'direct'
os.environ['PGSSLSNI'] = '1'
conn = psycopg2.connect(
    host="your-statbus-domain.com",
    port=5432,
    dbname="statbus",
    user="your_username",
    password="your_password",
    sslmode="verify-full"
)
```

#### R (RPostgres)

```r
library(RPostgres)

# Set environment variables for TLS/SNI
Sys.setenv(PGSSLNEGOTIATION = "direct")
Sys.setenv(PGSSLSNI = "1")

# Connect to StatBus
con <- dbConnect(
  RPostgres::Postgres(),
  host = "your-statbus-domain.com",
  port = 5432,
  dbname = "statbus",
  user = "your_username",
  password = "your_password",
  sslmode = "verify-full"
)

# Query data
result <- dbGetQuery(con, "SELECT * FROM public.legal_unit LIMIT 10")

# Close connection
dbDisconnect(con)
```

#### Node.js (pg)

```javascript
const { Client } = require('pg');

const client = new Client({
  host: 'your-statbus-domain.com',
  port: 5432,
  database: 'statbus',
  user: 'your_username',
  password: 'your_password',
  ssl: {
    rejectUnauthorized: true,  // verify-full mode
  }
});

// Set environment variables for TLS/SNI
process.env.PGSSLNEGOTIATION = 'direct';
process.env.PGSSLSNI = '1';

await client.connect();

// Query data
const result = await client.query('SELECT * FROM public.legal_unit LIMIT 10');
console.log(result.rows);

await client.end();
```

### Connection String Format

For database tools that support PostgreSQL connection strings:

```
postgresql://username:password@your-statbus-domain.com:5432/statbus?sslmode=verify-full&sslnegotiation=direct
```

**Important Security Notes:**
- Always use `sslmode=verify-full` for production connections
- Use environment variables for command-line tools to avoid exposing passwords
- Never commit connection strings with passwords to version control
- Store credentials securely in environment variables or credential managers

### Understanding TLS Parameters

StatBus uses modern TLS with SNI (Server Name Indication) for secure and efficient multi-tenant routing:

- **`PGSSLNEGOTIATION=direct`**: Use modern direct TLS instead of legacy STARTTLS protocol (PostgreSQL 17+ required)
- **`PGSSLMODE=verify-full`**: Full certificate verification - ensures encrypted connection and validates server identity
- **`PGSSLSNI=1`**: Send hostname as SNI during TLS handshake - critical for multi-tenant routing

### Troubleshooting

**Error: "SSL error: unexpected eof while reading"**
- Ensure you're using PostgreSQL 17+ client
- Verify `PGSSLNEGOTIATION=direct` is set
- Check that `PGSSLSNI=1` is set

**Error: "server certificate verification failed"**
- Using `sslmode=verify-full` with self-signed certificates
- For development/testing only: use `sslmode=require` (not recommended for production)

**Connection refused**
- Verify the StatBus domain and port are correct
- Check firewall settings allow connections to port 5432
- Ensure your IP address is allowed (if IP restrictions are enabled)

### Additional Resources

- [PostgreSQL 17 Connection Strings Documentation](https://www.postgresql.org/docs/17/libpq-connect.html)
- [PostgreSQL SSL Support](https://www.postgresql.org/docs/17/libpq-ssl.html)
- For deployment architecture details, see [Service Architecture](../service-architecture.md)