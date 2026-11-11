# StatBus REST API Reference for Data Consumers

This reference lists the REST API endpoints most useful for **data consumers** — analysts, researchers, and integrators who want to query statistical data, look up business units, and browse reference classifications.

All endpoints are served by [PostgREST](https://postgrest.org/) and follow its query syntax. Replace `https://ma.statbus.org` with your actual instance URL (e.g. `https://dev.statbus.org`).

> **Try it now:** Every URL below can be pasted directly into a browser. You will get JSON back. Add `&limit=5` to any query to keep the response short while exploring.

## Authentication

Most read endpoints require a valid API key. Pass it as a Bearer token:

```
Authorization: Bearer YOUR_API_KEY
```

To get your API key, log into the web interface and open **Show API key** in the command palette (Ctrl/Cmd+K), or visit:

```
https://ma.statbus.org/rest/api_key?select=token
```

For browser exploration, the session cookie set by the web login works automatically — just stay logged in.

### Auth endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/rest/rpc/login` | Log in (sets session cookies) |
| POST | `/rest/rpc/logout` | Log out (clears cookies) |
| POST | `/rest/rpc/refresh` | Refresh an expired access token |
| GET | `/rest/rpc/auth_status` | Check current authentication state |
| POST | `/rest/rpc/create_api_key` | Create an API key for scripted access |
| POST | `/rest/rpc/revoke_api_key` | Revoke a key by its `jti` (`{"key_jti": "..."}`) |

A key that has leaked can be replaced with **Recreate key** in the API key dialog, which creates a new key and revokes the old one.

---

## Statistical History (aggregated time series)

The main endpoint for retrieving aggregated counts of business units over time.

### `GET /rest/statistical_history`

**Sample browser URLs:**
```
https://ma.statbus.org/rest/statistical_history?select=year,countable_count&unit_type=eq.establishment&resolution=eq.year
https://ma.statbus.org/rest/statistical_history?select=year,countable_count&unit_type=eq.enterprise&resolution=eq.year
https://ma.statbus.org/rest/statistical_history?select=year,countable_count&unit_type=eq.legal_unit&resolution=eq.year

```

**Parameters (PostgREST filters):**

| Parameter | Example | Description |
|-----------|---------|-------------|
| `select` | `year,countable_count` | Columns to return |
| `unit_type` | `eq.establishment` | Filter by unit type: `establishment`, `legal_unit`, `enterprise` |
| `resolution` | `eq.year` | Time resolution: `year`, `quarter`, `month` |
| `year` | `eq.2023` or `gte.2020` | Filter by year |
| `order` | `year.asc` | Sort order |
| `limit` | `10` | Max rows returned |

**Example response:**
```json
[
  {"year": 2020, "countable_count": 1234},
  {"year": 2021, "countable_count": 1456},
  {"year": 2022, "countable_count": 1589}
]
```

### `POST /rest/rpc/statistical_history_highcharts`

Returns statistical history pre-formatted for Highcharts visualizations.

---

## Statistical Units (search and browse)

### `GET /rest/statistical_unit`

The main view for searching and browsing statistical units (legal units, establishments, enterprises).

**Sample browser URL — first 10 units:**
```
https://ma.statbus.org/rest/statistical_unit?select=unit_type,name,physical_region_path,primary_activity_category_path&limit=10
```

**Sample browser URL — search by name:**
```
https://ma.statbus.org/rest/statistical_unit?select=unit_type,name&name=ilike.*ba*&limit=10
```

**Sample browser URL — establishments in a specific region:**
```
https://ma.statbus.org/rest/statistical_unit?select=name,physical_region_code,physical_region_path,primary_activity_category_path&unit_type=eq.establishment&physical_region_code=like.03*&limit=10
```

Region paths are `ltree` values built from region codes (e.g. `03.01`), so filter on `physical_region_code` with `like`, or on the path with `eq`. Replace `03` with a code from `/rest/region_used`.

**Sample browser URL — with coordinates, employees and turnover:**
```
https://ma.statbus.org/rest/statistical_unit?select=unit_type,physical_latitude,physical_longitude,name,employees:stats->employees->>value,turnover:stats->turnover->>value&limit=10
```

**Useful columns:**

| Column | Description |
|--------|-------------|
| `unit_type` | `legal_unit`, `establishment`, or `enterprise` |
| `name` | Unit name |
| `external_idents` | External identifiers (JSONB), e.g. `{"tax_ident": "...", "stat_ident": "..."}`; the identifier types are listed in `/rest/external_ident_type_enabled` |
| `physical_region_path` | Physical location region hierarchy |
| `primary_activity_category_path` | Main industry classification path |
| `sector_path` | Institutional sector |
| `legal_form_name` | Legal form |
| `physical_latitude` | Latitude coordinate |
| `physical_longitude` | Longitude coordinate |
| `valid_from` | Start of validity period |
| `valid_to` | End of validity period |
| `existence_from`, `existence_until` | When the unit exists (birth/death dates applied); use these to ask "which units exist on a date", see [Time frames](#time-frames) |
| `stats` | JSONB with the unit's own statistical values (see below) |
| `stats_summary` | JSONB with aggregated stats across the unit hierarchy |

#### Accessing statistical variables (employees, turnover, etc.)

Statistical variables like `employees` and `turnover` are **not top-level columns** — they are stored inside the `stats` JSONB column, each as `{"type": "int", "value": 12}`. Use PostgREST JSON operators to extract them, and name the result with `alias:` so two values do not share a key:

| What you want | PostgREST select syntax |
|---------------|------------------------|
| Unit's own employees | `employees:stats->employees->>value` |
| Unit's own turnover | `turnover:stats->turnover->>value` |
| All stats as JSON | `stats` |
| Aggregated employee sum | `employees_sum:stats_summary->employees->>sum` |
| Aggregated turnover sum | `turnover_sum:stats_summary->turnover->>sum` |

`stats_summary` also holds `count`, `min`, `max`, `mean` and more for each variable.

**Sample browser URL — enterprise-level aggregated stats:**
```
https://ma.statbus.org/rest/statistical_unit?select=name,employees_sum:stats_summary->employees->>sum,turnover_sum:stats_summary->turnover->>sum&unit_type=eq.enterprise&limit=10
```

To see which statistical variables are defined in your instance:
```
https://ma.statbus.org/rest/stat_definition_enabled?select=code,name,description,type&order=code.asc
```

### `GET /rest/rpc/statistical_unit_details`

Full details for a single statistical unit.

```
https://ma.statbus.org/rest/rpc/statistical_unit_details?unit_id=1&unit_type=legal_unit
```

### `GET /rest/rpc/statistical_unit_hierarchy`

Returns the parent-child hierarchy for a unit (enterprise > legal unit > establishment).

```
https://ma.statbus.org/rest/rpc/statistical_unit_hierarchy?unit_id=1&unit_type=legal_unit
```

### `GET /rest/rpc/statistical_unit_stats`

Statistical variable values for a specific unit.

```
https://ma.statbus.org/rest/rpc/statistical_unit_stats?unit_id=1&unit_type=legal_unit
```

### `POST /rest/rpc/statistical_unit_facet_drilldown`

Faceted drilldown for building reports — filter by region, activity, sector, etc.

---

## Core Entity Tables

Direct access to the underlying business entity tables, for more detailed queries. Identifiers such as `tax_ident` and `stat_ident` live in `external_ident`, one row per identifier (`statistical_unit.external_idents` has them all in one JSON object).

### `GET /rest/legal_unit`

**Sample browser URL:**
```
https://ma.statbus.org/rest/legal_unit?select=id,name,birth_date,valid_from,valid_to&limit=10&order=id.asc
```

### `GET /rest/establishment`

**Sample browser URL:**
```
https://ma.statbus.org/rest/establishment?select=id,name,birth_date,valid_from,valid_to&limit=10&order=id.asc
```

### `GET /rest/external_ident`

**Sample browser URL — the identifiers of legal unit 1:**
```
https://ma.statbus.org/rest/external_ident?select=ident,type:external_ident_type(code)&legal_unit_id=eq.1
```

### `GET /rest/enterprise`

**Sample browser URL:**
```
https://ma.statbus.org/rest/enterprise?select=id,short_name,edit_at&limit=10&order=id.asc
```

---

## Reference Classifications

These endpoints provide the code lists and classifications used to categorize units.

### Activity categories (industry classification)

| Endpoint | Description |
|----------|-------------|
| `/rest/activity_category_standard` | All classification standards (ISIC, NACE, etc.) |
| `/rest/activity_category_enabled` | Currently enabled categories |
| `/rest/activity_category_used` | Categories actually assigned to units |

**Sample browser URL — browse enabled activity categories:**
```
https://ma.statbus.org/rest/activity_category_enabled?select=path,code,name,standard_code&limit=20&order=path.asc
```

### Regions (geography)

| Endpoint | Description |
|----------|-------------|
| `/rest/region` | All regions across all versions |
| `/rest/region_used` | Regions actually assigned to units |
| `/rest/region_version` | Available region classification versions |

**Sample browser URL — browse regions:**
```
https://ma.statbus.org/rest/region_used?select=path,code,name&limit=20&order=path.asc
```

### Legal forms

| Endpoint | Description |
|----------|-------------|
| `/rest/legal_form` | All legal forms |
| `/rest/legal_form_enabled` | Currently enabled legal forms |

**Sample browser URL:**
```
https://ma.statbus.org/rest/legal_form_enabled?select=code,name&order=code.asc
```

### Sectors (institutional sector)

| Endpoint | Description |
|----------|-------------|
| `/rest/sector` | All sectors |
| `/rest/sector_enabled` | Currently enabled sectors |

**Sample browser URL:**
```
https://ma.statbus.org/rest/sector_enabled?select=code,name&order=code.asc
```

### Countries

| Endpoint | Description |
|----------|-------------|
| `/rest/country` | All countries |
| `/rest/country_enabled` | Enabled countries |

**Sample browser URL:**
```
https://ma.statbus.org/rest/country_enabled?select=iso_2,name&order=name.asc
```

### Other classifications

| Endpoint | Description |
|----------|-------------|
| `/rest/unit_size` | Unit size ranges |
| `/rest/status` | Business statuses (active, inactive, etc.) |
| `/rest/data_source` | Data sources |
| `/rest/foreign_participation` | Foreign participation types |
| `/rest/external_ident_type` | Types of external identifiers |
| `/rest/stat_definition` | Statistical variable definitions |

Most of these have `_enabled` and `_ordered` variants (for example `/rest/status_enabled`, `/rest/data_source_ordered`).

---

## Statistical Variable Definitions

### `GET /rest/stat_definition`

Lists the statistical variables tracked for units (employees, turnover, etc.).

**Sample browser URL:**
```
https://ma.statbus.org/rest/stat_definition_enabled?select=code,name,description,type&order=code.asc
```

---

## Time frames

The data is a time series: each unit has records valid over date ranges. A **time frame** names the date you look at. The web interface's frame menu uses these same frames.

### `GET /rest/time_frame`

| `ident` | Kind | Meaning |
|---------|------|---------|
| `live` | `live` | Today; imports cover the current year onwards |
| `prev` | `relative` | The end of last year; moves forward each new year |
| `y_YYYY` | `fixed` | The end of year YYYY, e.g. `y_2024`; never moves |

Each row has `valid_on`, the date the frame looks at, and `valid_from`/`valid_to`, the period an import into that frame covers. The first row is the default.

**Sample browser URL:**
```
https://ma.statbus.org/rest/time_frame?select=ident,kind,name,valid_on&order=valid_on.desc
```

To list the units that exist in a frame, read its `valid_on` and filter on the existence columns:

```
https://ma.statbus.org/rest/statistical_unit?select=unit_type,name&existence_from=lte.2025-12-31&existence_until=gt.2025-12-31&limit=10
```

---

## PostgREST Query Syntax Quick Reference

All endpoints support PostgREST filtering. Common operators:

| Operator | Meaning | Example |
|----------|---------|---------|
| `eq` | Equals | `?unit_type=eq.establishment` |
| `neq` | Not equals | `?status=neq.inactive` |
| `gt`, `gte` | Greater than (or equal) | `?year=gte.2020` |
| `lt`, `lte` | Less than (or equal) | `?year=lt.2025` |
| `like` | Pattern match (case-sensitive) | `?name=like.*Corp*` |
| `ilike` | Pattern match (case-insensitive) | `?name=ilike.*bakery*` |
| `in` | In a list | `?unit_type=in.(legal_unit,establishment)` |
| `is` | IS (for null/boolean) | `?death_date=is.null` |
| `order` | Sort | `?order=name.asc` or `?order=year.desc` |
| `limit` | Max rows | `?limit=100` |
| `offset` | Skip rows (pagination) | `?offset=100` |
| `select` | Choose columns | `?select=name,code,path` |

Combine multiple filters by adding them as separate query parameters:
```
?unit_type=eq.establishment&year=gte.2020&order=year.asc&limit=50
```

### Getting row counts

Add the `Prefer: count=exact` header to get a total row count in the `Content-Range` response header:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     -H "Prefer: count=exact" \
     "https://ma.statbus.org/rest/statistical_unit?unit_type=eq.establishment&limit=0"
```

The response header `Content-Range: 0-0/1234` tells you there are 1234 matching rows.

---

## OpenAPI Specification

Your StatBus instance serves a live, auto-generated OpenAPI spec with every table, view, and function you can access. Request it with your API key:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" "https://ma.statbus.org/rest" > statbus-openapi.json
```

Load the saved file into [Swagger Editor](https://editor.swagger.io/) or any OpenAPI tool for an interactive, always-up-to-date reference of all available endpoints and their parameters.

---

## See Also

- [Integration Guide](../INTEGRATE.md) — Setup instructions for Python, R, and direct PostgreSQL access
- [Python example](python/example.py) — Working Python script with visualization
- [R example](r/example.r) — Working R script with visualization
- [PostgREST API interaction guide](../postgrest-api.md) — JavaScript client libraries and raw HTTP API
- [PostgREST documentation](https://postgrest.org/en/stable/) — Full query syntax reference
