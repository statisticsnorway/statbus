"use client";

import type { Column, Table } from "@tanstack/react-table";
import { ChevronsUpDown, X } from "lucide-react";
import * as React from "react";

import {
  Collapsible,
  CollapsibleContent,
} from "@/components/ui/collapsible";
import { DataTableDateFilter } from "@/components/data-table/data-table-date-filter";
import { DataTableFacetedFilter } from "@/components/data-table/data-table-faceted-filter";
import { DataTableSliderFilter } from "@/components/data-table/data-table-slider-filter";
import { DataTableViewOptions } from "@/components/data-table/data-table-view-options";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

interface DataTableToolbarProps<TData> extends React.ComponentProps<"div"> {
  table: Table<TData>;
}

export function DataTableToolbar<TData>({
  table,
  children,
  className,
  ...props
}: DataTableToolbarProps<TData>) {
  const isFiltered = table.getState().columnFilters.length > 0;

  const allFilterableColumns = table
    .getAllColumns()
    .filter((column) => !!column.columnDef.enableColumnFilter);

  const primaryFilters = allFilterableColumns.filter(
    (c) => c.columnDef.meta?.isPrimary,
  );
  const secondaryFilters = allFilterableColumns.filter(
    (c) => !c.columnDef.meta?.isPrimary,
  );

  const [isAdvancedSearchOpen, setIsAdvancedSearchOpen] = React.useState(false);

  const onReset = React.useCallback(() => {
    table.resetColumnFilters();
  }, [table]);

  return (
    <div
      role="toolbar"
      aria-orientation="vertical"
      className={cn("flex w-full flex-col items-start gap-2 p-1", className)}
      {...props}
    >
      <div className="flex w-full items-start justify-between gap-2">
        <div className="flex flex-1 flex-wrap items-center gap-2">
          {primaryFilters.map((column) => (
            <DataTableToolbarFilter key={column.id} column={column} />
          ))}

          {secondaryFilters.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              className="h-8 border-dashed"
              onClick={() => setIsAdvancedSearchOpen((prev) => !prev)}
            >
              <ChevronsUpDown className="mr-2 h-4 w-4" />
              More Filters
              <span className="ml-2 rounded-md bg-zinc-100 px-2 py-1 text-xs font-medium text-zinc-900 dark:bg-zinc-800 dark:text-zinc-50">
                {secondaryFilters.length}
              </span>
            </Button>
          )}

          {isFiltered && (
            <Button
              aria-label="Reset filters"
              variant="outline"
              size="sm"
              className="border-dashed"
              onClick={onReset}
            >
              <X />
              Reset
            </Button>
          )}
        </div>
        <div className="flex items-center gap-2">
          {children}
          <DataTableViewOptions table={table} />
        </div>
      </div>
      {secondaryFilters.length > 0 && (
        <Collapsible open={isAdvancedSearchOpen} className="w-full">
          <CollapsibleContent>
            <div className="flex flex-wrap items-center gap-2 rounded-md border border-dashed p-2">
              {secondaryFilters.map((column) => (
                <DataTableToolbarFilter key={column.id} column={column} />
              ))}
            </div>
          </CollapsibleContent>
        </Collapsible>
      )}
    </div>
  );
}
interface DataTableToolbarFilterProps<TData> {
  column: Column<TData>;
}

function DataTableToolbarFilter<TData>({
  column,
}: DataTableToolbarFilterProps<TData>) {
  const columnMeta = column.columnDef.meta;

  if (!columnMeta?.variant) return null;

  switch (columnMeta.variant) {
    case "text":
      return (
        <Input
          placeholder={columnMeta.placeholder ?? columnMeta.label}
          value={(column.getFilterValue() as string) ?? ""}
          onChange={(event) => column.setFilterValue(event.target.value)}
          className="h-8 w-40 lg:w-56"
        />
      );

    case "number":
      return (
        <div className="relative">
          <Input
            type="number"
            inputMode="numeric"
            placeholder={columnMeta.placeholder ?? columnMeta.label}
            value={(column.getFilterValue() as string) ?? ""}
            onChange={(event) => column.setFilterValue(event.target.value)}
            className={cn("h-8 w-[120px]", columnMeta.unit && "pr-8")}
          />
          {columnMeta.unit && (
            <span className="absolute top-0 right-0 bottom-0 flex items-center rounded-r-md bg-zinc-100 px-2 text-zinc-500 text-sm dark:bg-zinc-800 dark:text-zinc-400">
              {columnMeta.unit}
            </span>
          )}
        </div>
      );

    case "range":
      return (
        <DataTableSliderFilter
          column={column}
          title={columnMeta.label ?? column.id}
        />
      );

    case "date":
    case "dateRange":
      return (
        <DataTableDateFilter
          column={column}
          title={columnMeta.label ?? column.id}
          multiple={columnMeta.variant === "dateRange"}
        />
      );

    case "select":
    case "multiSelect":
      return (
        <DataTableFacetedFilter
          column={column}
          title={columnMeta.label ?? column.id}
          options={columnMeta.options ?? []}
          multiple={columnMeta.variant === "multiSelect"}
        />
      );

    default:
      return null;
  }
}
