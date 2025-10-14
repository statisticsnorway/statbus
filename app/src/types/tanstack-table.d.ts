import type { RowData } from "@tanstack/react-table";

// This file is used to augment the types of @tanstack/react-table
// See: https://tanstack.com/table/v8/docs/api/core/column-def#meta
declare module "@tanstack/react-table" {
  // We are extending the ColumnMeta interface to include our custom properties.
  // This provides type safety and autocompletion for these properties.
  interface ColumnMeta<TData extends RowData, TValue> {
    isPrimary?: boolean;
  }
}
