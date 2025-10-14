# Data Table Implementation Notes

This document covers key implementation details and conventions for using the data table components, which are built on `@tanstack/react-table`.

## Manual Filtering with `useReactTable`

When implementing a data table with server-side (manual) filtering, several configuration options must be set correctly on both the table instance and the column definitions for the filter UI to appear.

### Table-Level Configuration

The `useReactTable` hook requires the following options to be set to `true`:

- `manualFiltering: true`: Informs the table that filtering logic is handled externally (e.g., by a server API).
- `enableFilters: true`: The master switch for all filtering features.
- `enableColumnFilters: true`: Specifically enables column-level filtering.

Without all three of these, the filtering UI will not render.

```tsx
// Example from app/src/app/import/jobs/[jobSlug]/data/page.tsx

const table = useReactTable({
  // ... other options
  manualFiltering: true,
  enableFilters: true,
  enableColumnFilters: true,
  // ... other options
});
```

### Column-Level Configuration

For each column that should be filterable, the `ColumnDef` must include:

- `enableColumnFilter: true`: Enables filtering for this specific column.
- `filterFn`: **This is mandatory.** Even in `manualFiltering` mode where the function is never executed, `@tanstack/react-table`'s internal logic requires a `filterFn` to be present for the filter UI to be enabled for that column. A simple placeholder function is sufficient.

```tsx
// Example placeholder from app/src/app/import/jobs/[jobSlug]/data/page.tsx

const placeholderFilterFn: FilterFn<MyDataType> = (row, columnId, value, addMeta) => true;

// Example ColumnDef
const columnDef: ColumnDef<MyDataType> = {
  id: 'my_column_raw', // The ID used in the API query
  enableColumnFilter: true,
  filterFn: placeholderFilterFn,
  meta: {
    label: 'My Column',
    variant: 'text',
  },
  // ... other properties
};
```

### The `getCanFilter()` Anomaly and Workaround

During development, we discovered that even with the correct table and column configurations, the `column.getCanFilter()` method provided by `@tanstack/react-table` incorrectly returned `false` when `manualFiltering: true` was active. This prevented the `DataTableToolbar` from rendering any filter inputs.

To resolve this, the `DataTableToolbar` was modified to bypass this method. Instead of relying on `getCanFilter()`, it directly inspects the column definition to determine if a column is filterable.

**This is a critical convention for our project:**

The toolbar determines filterability by checking if `column.columnDef.enableColumnFilter` is truthy.

```tsx
// From app/src/components/data-table/data-table-toolbar.tsx

// Instead of:
// const columns = table.getAllColumns().filter((column) => column.getCanFilter());

// We use:
const columns = table.getAllColumns().filter((column) => !!column.columnDef.enableColumnFilter);
```

This ensures that our UI reliably reflects the developer's intent as specified in the `ColumnDef`, regardless of the library's internal behavior in manual filtering mode.
