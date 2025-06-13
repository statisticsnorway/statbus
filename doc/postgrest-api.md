# PostgREST JavaScript Client (@supabase/postgrest-js) API Summary

This document summarizes the API for `@supabase/postgrest-js`, an isomorphic JavaScript client for PostgREST.

## Installation

```bash
npm install @supabase/postgrest-js
```

## Initialization

To use the client, import `PostgrestClient` and instantiate it with your PostgREST API URL.

```javascript
import { PostgrestClient } from '@supabase/postgrest-js';

// Replace with your PostgREST URL, e.g., http://localhost:3000
const REST_URL = 'your_postgrest_instance_url'; 
const postgrest = new PostgrestClient(REST_URL);
```

### Custom Fetch Implementation

A custom `fetch` implementation can be provided. This is useful in environments where the default `cross-fetch` might not be suitable (e.g., Cloudflare Workers).

```javascript
const postgrest = new PostgrestClient(REST_URL, {
  fetch: (...args) => fetch(...args), // Provide your custom fetch function
});
```

## Core Methods

The client provides methods for common CRUD operations. These methods are typically chained with filters and modifiers.

### `select()`

Used for querying data from a table or view.

**Syntax:**
`.select(columns, options)`

-   `columns` (optional): A string of comma-separated column names. Defaults to `*` (all columns).
    -   Can include computed columns and foreign table embedding (joins). Example: `'columnA, columnB, foreign_table(foreign_column1, foreign_column2)'`.
    -   Rename columns: `'new_name:old_name, other_new_name:other_old_name'`.
    -   Cast columns: `'my_column::text'`.
    -   JSON properties: `'my_json_column->>property_name'`.
-   `options` (optional): An object with the following properties:
    -   `head`: `boolean` - If `true`, retrieves only the headers and not the data. Defaults to `false`.
    -   `count`: `null | 'exact' | 'planned' | 'estimated'` - Specifies how to count the total number of rows.
        -   `'exact'`: Accurate count.
        -   `'planned'`: Faster, estimated count based on planner.
        -   `'estimated'`: Fastest, estimated count from statistics.
        -   If set, the result will include a `count` property.

**Examples:**

Select all columns:
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .select();
```

Select specific columns:
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .select('column_one, column_two');
```

Select with count:
```javascript
const { data, error, count } = await postgrest
  .from('your_table')
  .select('*', { count: 'exact' });
```

Embedding foreign tables (joins):
```javascript
// Assuming 'cities' has a foreign key to 'countries'
const { data, error } = await postgrest
  .from('cities')
  .select('name, countries(name)');
```

**Modifiers (can be chained):**
-   Filters: `eq()`, `neq()`, `gt()`, `gte()`, `lt()`, `lte()`, `like()`, `ilike()`, `is()`, `in()`, `contains()`, `containedBy()`, `rangeGt()`, `rangeGte()`, `rangeLt()`, `rangeLte()`, `rangeAdjacent()`, `overlaps()`, `textSearch()`, `match()`, `not()`, `or()`, `filter()`.
    ```javascript
    // Example: .eq('column_name', 'value')
    // Example: .like('column_name', '%pattern%')
    // Example: .textSearch('fts_column', "'search' & 'terms'")
    ```
-   `order(column, options)`: Sorts the result.
    -   `options`: `{ ascending?: boolean, nullsFirst?: boolean, foreignTable?: string }`.
-   `limit(count, options)`: Limits the number of rows returned.
    -   `options`: `{ foreignTable?: string }`.
-   `range(from, to, options)`: Retrieves a range of rows (pagination).
    -   `options`: `{ foreignTable?: string }`.
-   `single()`: Returns a single row. Throws an error if not exactly one row is found.
-   `maybeSingle()`: Returns a single row or `null`. Throws an error if more than one row is found.
-   `csv()`: Returns the data as a CSV string.
-   `geojson(geometryColumn, options)`: Returns GeoJSON output (for PostGIS).
    - `options`: `{ crs?: string, type?: 'Point' | 'MultiPoint' | 'LineString' | 'MultiLineString' | 'Polygon' | 'MultiPolygon' | 'GeometryCollection' }`
-   `explain(options)`: Returns the query plan.
    - `options`: `{ analyze?: boolean, verbose?: boolean, settings?: boolean, buffers?: boolean, wal?: boolean, format?: 'text' | 'json' }`

### `insert()`

Used for inserting new rows into a table.

**Syntax:**
`.insert(rows, options)`

-   `rows`: A single object or an array of objects representing the rows to insert.
-   `options` (optional): An object with the following properties:
    -   `returning`: `'minimal' | 'representation'` - `'minimal'` (default) returns nothing. `'representation'` returns the inserted rows.
    -   `count`: `null | 'exact' | 'planned' | 'estimated'` - Specifies how to count the affected rows.
    -   `defaultToNull`: `boolean` - If `true` (default), columns not specified in the `rows` object will be set to `NULL` if they don't have a default value in the database. If `false`, such columns will use their database default or trigger an error if no default exists.

**Examples:**

Insert a single row:
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .insert({ column1: 'value1', column2: 'value2' });
```

Insert multiple rows and return them:
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .insert([
    { column1: 'valueA', column2: 'valueB' },
    { column1: 'valueC', column2: 'valueD' }
  ], { returning: 'representation' });
```

**Related Method: `upsert()`**
Used to insert rows, or update them if they already exist (based on a conflict target).

**Syntax:**
`.upsert(rows, options)`
-   `rows`: A single object or an array of objects.
-   `options` (optional):
    -   `onConflict`: `string` - Comma-separated list of columns for conflict resolution.
    -   `ignoreDuplicates`: `boolean` - If `true`, duplicate rows (based on `onConflict`) are ignored. Defaults to `false`.
    -   `returning`: `'minimal' | 'representation'`.
    -   `count`: `null | 'exact' | 'planned' | 'estimated'`.
    -   `defaultToNull`: `boolean`.

```javascript
const { data, error } = await postgrest
  .from('your_table')
  .upsert({ id: 1, name: 'New Name' }, { onConflict: 'id' });
```

### `update()`

Used for updating existing rows in a table. Requires filter(s) to specify which rows to update.

**Syntax:**
`.update(values, options)`

-   `values`: An object containing the column-value pairs to update.
-   `options` (optional): An object with the following properties:
    -   `returning`: `'minimal' | 'representation'` - `'minimal'` (default). `'representation'` returns the updated rows.
    -   `count`: `null | 'exact' | 'planned' | 'estimated'`.
    -   `defaultToNull`: `boolean`.

**Example:**
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .update({ status: 'active', other_column: 'new_value' })
  .eq('id', 123) // Must specify which rows to update
  .select(); // To get the updated rows (if not using returning: 'representation')
```

With `returning: 'representation'`:
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .update({ status: 'inactive' }, { returning: 'representation' })
  .eq('category', 'old_category');
```

### `delete()`

Used for deleting rows from a table. Requires filter(s) to specify which rows to delete.

**Syntax:**
`.delete(options)`

-   `options` (optional): An object with the following properties:
    -   `returning`: `'minimal' | 'representation'` - `'minimal'` (default). `'representation'` returns the deleted rows.
    -   `count`: `null | 'exact' | 'planned' | 'estimated'`.

**Example:**
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .delete()
  .eq('id', 456); // Must specify which rows to delete
```

Delete and return the deleted rows:
```javascript
const { data, error } = await postgrest
  .from('your_table')
  .delete({ returning: 'representation' })
  .lt('created_at', '2023-01-01');
```

## Calling Postgres Functions (`rpc()`)

PostgREST allows calling database functions (stored procedures) using the `rpc()` method.

**Syntax:**
`.rpc(name, params, options)`

-   `name`: `string` - The name of the Postgres function to call.
-   `params` (optional): `object` - An object containing the parameters to pass to the function.
-   `options` (optional): `object` - An object with the following properties:
    -   `method`: `'POST' | 'GET'` - The HTTP method to use. Defaults to `'POST'`. Use `'GET'` for read-only functions (idempotent). This is how you achieve the "get" behavior.
    -   `head`: `boolean` - If `true`, retrieves only the headers. Defaults to `false`.
    -   `count`: `null | 'exact' | 'planned' | 'estimated'` - Specifies how to count rows if the function returns a set.

**Examples:**

Call a function with parameters (defaults to POST):
```javascript
const { data, error } = await postgrest
  .rpc('my_function_name', { param1: 'value1', param2: 100 });
```

Call a read-only function using GET:
```javascript
const { data, error } = await postgrest
  .rpc('get_report_data', { report_id: 7 }, { method: 'GET' });
```

Call a function and get a count of returned rows:
```javascript
const { data, error, count } = await postgrest
  .rpc('list_items', { category: 'electronics' }, { count: 'exact', method: 'GET' });
```

If the function returns a set of rows (e.g., `SETOF sometable` or `RETURNS TABLE(...)`), you can chain `select()`, filters, `order()`, `limit()`, and `range()` modifiers just like with `.from('table').select()`.

```javascript
const { data, error } = await postgrest
  .rpc('get_user_activity', { user_id: 123 }, { method: 'GET' })
  .select('activity_type, created_at')
  .order('created_at', { ascending: false })
  .limit(10);
```

---
This summary is based on the PostgREST JavaScript client documentation. For the most comprehensive and up-to-date information, always refer to the official Supabase and PostgREST documentation.
