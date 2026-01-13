# StatBus User Guide

This guide is for **statisticians, analysts, and data managers** who want to use StatBus to manage and analyze business registry data.

## Table of Contents

- [Getting Started](#getting-started)
- [Accessing Your StatBus Instance](#accessing-your-statbus-instance)
- [Loading Data](#loading-data)
- [Integrating with StatBus](#integrating-with-statbus)
- [User Management](#user-management)
- [Cloud Testing Environment](#cloud-testing-environment)

---

## Getting Started

### What is StatBus?

StatBus is a statistical business registry system that tracks business activity throughout history using temporal tables. It allows you to:

- Manage classifications (activity categories, regions, sectors, legal forms)
- Track legal units and establishments over time
- Query data at any point in history
- Generate reports and export data
- Access data via web interface, REST API, or direct PostgreSQL connection

### Access Levels

StatBus has four user roles:

- **admin_user**: Full system access - can manage users, settings, and all data
- **regular_user**: Can enter and edit data - but not change setup/classifications
- **restricted_user**: Can only insert/edit data for selected regions or activity categories
- **external_user**: Read-only access - can view everything but not change anything

Contact your StatBus administrator to get your username and password.

---

## Accessing Your StatBus Instance

### Web Interface

1. **Open your StatBus URL** in a web browser (provided by your administrator)
   - Example: `https://statbus.example.com`
   
2. **Log in** with your username and password

3. **Dashboard**: After logging in, you'll see the main dashboard with:
   - Summary statistics
   - Recent activity
   - Quick actions menu

### Using the Command Palette

Press **Ctrl+Shift+K** (or Cmd+Shift+K on Mac) to open the command palette. This provides quick access to:

- Data loading functions
- Report generation
- Refresh materialized views
- Database management (admin only)

---

## Loading Data

StatBus requires data to be loaded in a specific order to maintain referential integrity. Use the command palette (Ctrl+Shift+K) to access data loading options.

### Loading Sequence

Follow this order when loading data for the first time:

#### 1. Select Activity Standard

Choose your country's activity classification system:
- **NACE**: European standard (StatBus includes Norwegian translations)
- **ISIC**: International standard
- **NAICS**: North American standard
- **Custom**: Your own classification system

#### 2. Upload Classifications

Load classifications in this order:

**a) Regions** (geographic areas)
- Download sample CSV from "What is Region file?" in the command palette
- Format: code, name, parent_code (for hierarchical regions)
- Example: `NO-03, Oslo, NO` (Oslo region, parent Norway)

**b) Sectors** (institutional sectors)
- Download sample CSV
- Format: code, name, description
- Example: `S11, Non-financial corporations`

**c) Legal Forms** (company types)
- Download sample CSV  
- Format: code, name, description
- Example: `AS, Aksjeselskap, Norwegian stock company`

**d) Custom Activity Categories** (optional)
- Contains translations and local variations of activity codes
- Useful for adding Norwegian translations to NACE codes
- Format: code, name, description, parent_code

#### 3. Upload Units

After classifications are loaded, upload your business units:

**a) Legal Units** (companies, organizations)
- Must reference valid: regions, sectors, legal forms, activity categories
- Sample data uses Norwegian regions and NACE codes
- Format: tax_ident, name, birth_date, death_date, etc.

**b) Establishments** (physical locations)
- Must reference valid legal units
- Sample data uses Norwegian regions and NACE codes  
- Format: tax_ident, legal_unit_id, name, address, etc.

#### 4. Refresh Materialized Views

After loading data, refresh materialized views using the command palette (Ctrl+Shift+K):
- Select "Refresh materialized views"
- This updates summary tables and dashboard statistics

### Data Loading Tips

- **Start small**: Test with a small sample (10-100 units) before loading full dataset
- **Validate classifications**: Ensure all referenced codes exist before loading units
- **Check data format**: Download sample CSV files to see expected format
- **Backup regularly**: Use the export functionality before making major changes
- **Incremental loading**: You can add more data after initial load

### Sample/Demo Data

StatBus includes sample data files for testing and demonstration:

- **Activity Categories**: Sample data uses **ISIC** (International Standard Industrial Classification) as most StatBus countries use this standard
- **Regions**: Demo files show how to define region hierarchies in CSV format
- **Units**: Sample legal units and establishments for testing

**To use demo data**:
1. Open command palette (Ctrl+Shift+K)
2. Select data loading options
3. Download sample CSV files from the prompts
4. Upload sample files to see StatBus in action
5. You can delete and reload data as needed for testing

### Resetting Data

To start over with a clean database:
1. Open command palette (Ctrl+Shift+K)
2. Select "Reset all data" (admin only)
3. Confirm the operation
4. Reload classifications and units

---

## Integrating with StatBus

StatBus provides multiple ways to access and integrate data:

### 1. REST API

Best for web applications and scripting (Python, R, JavaScript).

**Learn more**: See [Integration Guide](INTEGRATE.md#rest-api)

**Quick example** (Python):
```python
import requests

# Get your API key from: https://your-statbus-url/rest/api_key?select=token
api_url = "https://your-statbus-url"
api_key = "your-api-key-here"

headers = {"Authorization": f"Bearer {api_key}"}
response = requests.get(f"{api_url}/rest/legal_unit?limit=10", headers=headers)
units = response.json()
```

### 2. PostgreSQL Direct Access

Best for SQL tools, data analysis, and bulk operations.

**Learn more**: See [Integration Guide](INTEGRATE.md#postgresql-direct-access)

**Quick example** (psql):
```bash
# Set connection parameters
export PGHOST=your-statbus-domain.com
export PGPORT=5432
export PGDATABASE=statbus
export PGUSER=your_username
export PGPASSWORD=your_password
export PGSSLNEGOTIATION=direct
export PGSSLMODE=verify-full
export PGSSLSNI=1

# Connect
psql

# Query data
SELECT * FROM public.legal_unit LIMIT 10;
```

**Supported tools**:
- **psql**: PostgreSQL command-line client
- **pgAdmin**: Graphical administration tool
- **DBeaver**: Universal database tool
- **Python**: psycopg2, psycopg3, SQLAlchemy
- **R**: RPostgres, DBI
- **Node.js**: pg, pg-promise

### 3. GraphQL API

StatBus includes pg_graphql for GraphQL queries.

**Endpoint**: `https://your-statbus-url/rest/rpc/graphql`

---

## User Management

### Changing Your Password

1. Log in to StatBus web interface
2. Click your username in the top right
3. Select "Change Password"
4. Enter current password and new password
5. Click "Update"

### Getting an API Key

1. Log in to StatBus web interface
2. Visit: `https://your-statbus-url/rest/api_key?select=token`
3. Copy the token value
4. Store it securely (treat it like a password)

### Managing Users (Admin Only)

Administrators can manage users through:
- Web interface: User Management section
- Command palette: "Manage Users"
- Direct SQL: `SELECT * FROM admin.users;`

---

## Cloud Testing Environment

Before deploying StatBus locally or for production, we recommend testing in the cloud environment:

### Benefits

- **No installation required**: Test immediately without setup
- **Country-specific**: Get a dedicated domain for your country
- **Pre-configured**: Standard classifications already loaded
- **Validation**: Verify the data model fits your needs
- **Training**: Learn the system before committing to deployment

### Getting Access

Contact Statistics Norway (SSB) to request:
- A dedicated testing domain (e.g., `your-country.statbus.org`)
- Admin credentials for your instance
- Sample data tailored to your country's classifications

### Testing Workflow

1. **Get access**: Request your testing instance
2. **Load sample data**: Use provided sample files for your country
3. **Test classifications**: Verify activity codes, regions match your needs
4. **Test workflows**: Try data loading, querying, reporting
5. **Evaluate**: Determine if StatBus meets your requirements
6. **Deploy locally**: Once validated, proceed with local installation

### More Information

- Detailed guides: https://www.statbus.org/files/Statbus_faq_load.html
- Contact SSB: Visit https://www.statbus.org for contact information

---

## Getting Help

### Documentation Resources

- **[Integration Guide](INTEGRATE.md)**: REST API and PostgreSQL connection examples
- **[Service Architecture](doc/service-architecture.md)**: Technical architecture details
- **[Deployment Guide](doc/DEPLOYMENT.md)**: For administrators deploying single instance
- **[Cloud Guide](doc/CLOUD.md)**: For SSB staff managing multi-tenant cloud
- **[Development Guide](doc/DEVELOPMENT.md)**: For developers contributing to StatBus

### Support

- **Issue Tracker**: https://github.com/statisticsnorway/statbus/issues
- **Website**: https://www.statbus.org
- **Email**: Contact your StatBus administrator or SSB

### FAQ

**Q: Can I export data to Excel?**  
A: Yes, use the export functionality or connect Excel directly via PostgreSQL ODBC driver.

**Q: How do I query historical data?**  
A: Use temporal queries with valid_from/valid_to dates. Example: `SELECT * FROM legal_unit WHERE '2023-01-01' BETWEEN valid_from AND valid_to;`

**Q: What happens if I upload duplicate data?**  
A: StatBus will reject duplicates based on unique identifiers (tax_ident). Update existing records instead.

**Q: Can multiple users edit data simultaneously?**  
A: Yes, StatBus supports concurrent editing with row-level locking.

**Q: How do I backup my data?**  
A: Contact your administrator for database backup procedures. Users can export data via REST API or PostgreSQL.
