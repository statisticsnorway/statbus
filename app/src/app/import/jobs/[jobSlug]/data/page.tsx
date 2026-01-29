"use client";

import React from "react";
import { useParams } from 'next/navigation';
import useSWR, { useSWRConfig } from 'swr';
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DataTableSkeleton } from "@/components/data-table/data-table-skeleton";
import { Skeleton } from "@/components/ui/skeleton";
import { Tables } from '@/lib/database.types';
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { 
  ColumnDef, PaginationState, SortingState, ColumnFiltersState, FilterFn, Row, VisibilityState,
  useReactTable, getCoreRowModel, getFilteredRowModel, getPaginationRowModel, getSortedRowModel, getFacetedRowModel, getFacetedUniqueValues, getFacetedMinMaxValues 
} from "@tanstack/react-table";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { ChevronRight, AlertTriangle } from "lucide-react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useAtomValue } from "jotai";
import { externalIdentTypesAtom } from "@/atoms/base-data";
import { type ImportJobWithDetails as ImportJob } from "@/atoms/import";
import { ErrorDisplay } from "@/components/import/ErrorDisplay";
// Per instruction, improve typing for ImportJobDataRow to make 'state' work
// in useDataTable. This is a first step, with 'any' types to be refined.
type ImportJobDataRow = {
  row_id: number;
  state: any;
  name?: string | null;
  operation?: any;
  action?: any;
  errors?: any;
  invalid_codes?: any;
  merge_status?: any;
  [key:string]: any;
};

// For manual filtering, tanstack-table's `getCanFilter()` returns true only if a `filterFn` is defined.
// The function itself is never called, but its presence (with the correct signature) is required to enable the UI.
const placeholderFilterFn: FilterFn<ImportJobDataRow> = (
  row: Row<ImportJobDataRow>,
  columnId: string,
  value: any,
  addMeta: (meta: any) => void
) => true;

const fetcher = async (key: string): Promise<any> => {
  const client = await getBrowserRestClient();
  if (!client) throw new Error("REST client not available");

  const [type, ...args] = key.split('/');

  if (type === 'import-job' && args[0]) {
    const { data, error } = await client
      .from("import_job")
      .select("*, import_definition(name)")
      .eq("slug", args[0])
      .single();
    if (error) throw error;
    return data;
  }

  if (type === 'import-data' && args[0]) {
    const [tableName, query] = args[0].split('?');
    const searchParams = new URLSearchParams(query);
    const page = parseInt(searchParams.get('page') || '0', 10);
    const pageSize = parseInt(searchParams.get('pageSize') || '10', 10);
    const sortingParams = searchParams.getAll('sort');

    const from = page * pageSize;
    const to = from + pageSize - 1;

    let queryBuilder = client
      .from(tableName as any)
      .select('*', { count: 'exact' })
      .range(from, to);
    
    sortingParams.forEach(sort => {
      const [id, dir] = sort.split('.');
      if (id && dir) {
        queryBuilder = queryBuilder.order(id, { ascending: dir === 'asc' });
      }
    });

    const filters = new Map<string, string[]>();
    for (const [key, value] of searchParams.entries()) {
      if (key !== 'page' && key !== 'pageSize' && key !== 'sort') {
        if (!filters.has(key)) {
          filters.set(key, []);
        }
        filters.get(key)!.push(value);
      }
    }

    filters.forEach((values, key) => {
      if (key === 'errors' || key === 'invalid_codes') {
        const filterValue = values[0];
        if (filterValue === 'is_null') {
          queryBuilder = queryBuilder.or(`${key}.is.null,${key}.eq.{}`);
        } else if (filterValue === 'not_null') {
          queryBuilder = queryBuilder.not(key, 'is', null).not(key, 'eq', '{}');
        }
      } else if (['operation', 'state', 'action'].includes(key)) {
        queryBuilder = queryBuilder.in(key, values);
      } else {
        // Text search for name, external idents, etc.
        queryBuilder = queryBuilder.ilike(key, `%${values[0]}%`);
      }
    });

    const { data, error, count } = await queryBuilder;

    if (error) throw error;
    return { data, count };
  }

  throw new Error(`Unrecognized SWR key: ${key}`);
};


export default function ImportJobDataPage() {
  const params = useParams();
  const jobSlug = typeof params.jobSlug === 'string' ? params.jobSlug : undefined;

  const { mutate } = useSWRConfig();
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);

  const [pagination, setPagination] = React.useState<PaginationState>({
    pageIndex: 0,
    pageSize: 10,
  });

  const [sorting, setSorting] = React.useState<SortingState>([
    { id: "row_id", desc: false },
  ]);

  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>([]);
  const [columnVisibility, setColumnVisibility] = React.useState<VisibilityState>({});

  const { data: job, error: jobError, isLoading: isJobLoading } = useSWR<ImportJob>(
    `import-job/${jobSlug}`,
    fetcher
  );

  const tableName = job?.data_table_name;

  const tableDataSWRKey = React.useMemo(() => {
    if (!tableName) return null;

    const params = new URLSearchParams();
    params.append('page', pagination.pageIndex.toString());
    params.append('pageSize', pagination.pageSize.toString());
    sorting.forEach(sort => {
      params.append('sort', `${sort.id}.${sort.desc ? 'desc' : 'asc'}`);
    });
    columnFilters.forEach(filter => {
      if (Array.isArray(filter.value)) {
        filter.value.forEach(val => params.append(filter.id, String(val)));
      } else if (filter.value) {
        params.append(filter.id, String(filter.value));
      }
    });

    return `import-data/${tableName}?${params.toString()}`;
  }, [tableName, pagination, sorting, columnFilters]);


  const { data: tableData, error: tableError, isLoading: isTableDataLoading, isValidating: isTableDataValidating } = useSWR<{
    data: ImportJobDataRow[];
    count: number | null;
  }>(
    tableDataSWRKey,
    fetcher,
    { revalidateOnFocus: false, keepPreviousData: true }
  );


  useGuardedEffect(() => {
    if (!job?.id) return;

    const sseUrl = `/api/sse/import-jobs?ids=${job.id}&scope=updates_for_ids_only`;
    const eventSource = new EventSource(sseUrl);

    eventSource.addEventListener('heartbeat', (event) => {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        const heartbeat = JSON.parse(event.data);
        console.log(`SSE Heartbeat for job ${job.id}:`, heartbeat);
      }
    });

    eventSource.onmessage = (event) => {
      try {
        if (!event.data) return;
        const ssePayload = JSON.parse(event.data);
        if (ssePayload.type === "connection_established") return;

        // If the update is for our job, revalidate SWR caches
        if (ssePayload.import_job?.id === job.id) {
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log(`SSE: Job ${job.id} updated, revalidating data page.`);
          }
          
          // Optimistically update the job details from the SSE payload
          if (ssePayload.verb === 'DELETE') {
            // If the job is deleted, clear the job data to show a "not found" message.
            mutate(`import-job/${jobSlug}`, null, { revalidate: false });
          } else {
            // For INSERT or UPDATE, inject the new data from the SSE payload
            mutate(`import-job/${jobSlug}`, ssePayload.import_job, { revalidate: false });
          }

          // Revalidate the table data as it has likely changed
          if (tableDataSWRKey) {
            mutate(tableDataSWRKey);
          }
        }
      } catch (error) {
        console.error("Error processing SSE message on data page:", error);
      }
    };

    eventSource.onerror = (err) => {
        console.error(`SSE connection error for job ${job.id}:`, err);
        eventSource.close();
    };

    return () => {
      eventSource.close();
    };
  }, [job?.id, jobSlug, tableDataSWRKey, mutate], 'ImportJobDataPage:sseListener');

  const pageCount = React.useMemo(() => {
    return tableData?.count != null
      ? Math.ceil(tableData.count / pagination.pageSize)
      : -1;
  }, [tableData?.count, pagination.pageSize]);

  const columns = React.useMemo<ColumnDef<ImportJobDataRow>[]>(() => {
    const operationOptions = [
      { label: 'insert', value: 'insert' }, { label: 'replace', value: 'replace' }, { label: 'update', value: 'update' }
    ];
    const stateOptions = [
      { label: 'pending', value: 'pending' }, { label: 'analysing', value: 'analysing' }, { label: 'analysed', value: 'analysed' },
      { label: 'processing', value: 'processing' }, { label: 'processed', value: 'processed' }, { label: 'error', value: 'error' }
    ];
    const actionOptions = [
      { label: 'insert', value: 'insert' }, { label: 'replace', value: 'replace' },
      { label: 'update', value: 'update' }, { label: 'skip', value: 'skip' }
    ];

    const externalIdentCodes = externalIdentTypes.map(e => e.code).filter((c): c is string => c !== null);
    const preferredOrder = [
      'row_id',
      'operation',
      'state',
      'action',
      'errors',
      'invalid_codes',
      'merge_status',
      ...externalIdentCodes,
      'name'
    ];
    const allKeys = new Set<string>();

    if (tableData?.data) {
        tableData.data.forEach(row => {
            Object.keys(row).forEach(key => allKeys.add(key));
        });
    }

    const baseKeys = new Set<string>();
    allKeys.forEach(key => {
        const activityMatch = key.match(/^(.*_activity)_category_code_raw$/);
        if (activityMatch) {
            baseKeys.add(activityMatch[1]); // e.g. primary_activity
        } else if (key.match(/^.*_activity_category_id$/) && allKeys.has(key.replace('_category_id', '_category_code_raw'))) {
            baseKeys.add(key.replace('_category_id', ''));
        } else if (key.match(/^.*_activity_id$/) && allKeys.has(key.replace('_id', '_category_code_raw'))) {
            baseKeys.add(key.replace('_id', ''));
        } else if (key.endsWith('_path_raw')) {
            baseKeys.add(key.slice(0, -9)); // e.g. 'tag' from 'tag_path_raw'
        } else if (key.endsWith('_path') && allKeys.has(key.slice(0, -5) + '_path_raw')) {
            baseKeys.add(key.slice(0, -5));
        } else if (key.endsWith('_code_raw')) {
            baseKeys.add(key.slice(0, -9)); // e.g. 'sector' from 'sector_code_raw'
        } else if (key.endsWith('_id') && (allKeys.has(key.slice(0, -3) + '_code_raw') || allKeys.has(key.slice(0, -3) + '_path_raw'))) {
            baseKeys.add(key.slice(0, -3));
        } else {
            baseKeys.add(key.replace(/_raw$/, '')); // This handles `name`/`name_raw` and standalone keys like `operation`
        }
    });

    let sortedBaseKeys = Array.from(baseKeys);

    sortedBaseKeys.sort((a, b) => {
      const aIndex = preferredOrder.indexOf(a);
      const bIndex = preferredOrder.indexOf(b);
      const aPos = aIndex === -1 ? preferredOrder.length : aIndex;
      const bPos = bIndex === -1 ? preferredOrder.length : bIndex;
      if (aPos !== bPos) return aPos - bPos;
      return a.localeCompare(b);
    });

    const finalColumns = sortedBaseKeys.map(baseKey => {
      const rawKey = `${baseKey}_raw`;
      const codeRawKey = `${baseKey}_code_raw`;
      const idKey = `${baseKey}_id`;
      const pathKey = `${baseKey}_path`;
      const pathRawKey = `${baseKey}_path_raw`;
      const activityCategoryCodeRawKey = `${baseKey}_category_code_raw`;
      const activityCategoryIdKey = `${baseKey}_category_id`;

      const hasPlain = allKeys.has(baseKey);
      const hasRaw = allKeys.has(rawKey);
      const hasCodeRaw = allKeys.has(codeRawKey);
      const hasId = allKeys.has(idKey);
      const hasPath = allKeys.has(pathKey);
      const hasPathRaw = allKeys.has(pathRawKey);
      const hasActivityCategoryCodeRaw = allKeys.has(activityCategoryCodeRawKey);
      const hasActivityCategoryId = allKeys.has(activityCategoryIdKey);


      const headerText = baseKey.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
      
      const columnDef: ColumnDef<ImportJobDataRow> = {
          id: baseKey, // Default ID, will be overridden for filters
          header: ({ column }) => <DataTableColumnHeader column={column} title={headerText} />,
          cell: ({ row }) => {
              const plainValue = hasPlain ? row.original[baseKey as keyof ImportJobDataRow] : undefined;
              const rawValue = hasRaw ? row.original[rawKey as keyof ImportJobDataRow] : undefined;
              const codeRawValue = hasCodeRaw ? row.original[codeRawKey as keyof ImportJobDataRow] : undefined;
              const idValue = hasId ? row.original[idKey as keyof ImportJobDataRow] : undefined;
              const pathValue = hasPath ? row.original[pathKey as keyof ImportJobDataRow] : undefined;
              const pathRawValue = hasPathRaw ? row.original[pathRawKey as keyof ImportJobDataRow] : undefined;
              const activityCategoryCodeRawValue = hasActivityCategoryCodeRaw ? row.original[activityCategoryCodeRawKey as keyof ImportJobDataRow] : undefined;
              const activityCategoryIdValue = hasActivityCategoryId ? row.original[activityCategoryIdKey as keyof ImportJobDataRow] : undefined;
              
              const renderSingleValue = (val: any, className: string = '') => {
                  if (val === undefined || val === null) return null;
                  let displayValue;
                  if (typeof val === 'object') {
                      displayValue = JSON.stringify(val);
                  } else {
                      displayValue = String(val);
                  }
                  return <div className={`text-xs truncate ${className}`} title={displayValue}>{displayValue}</div>;
              };

              // Special handling for errors and invalid_codes columns
              if (baseKey === 'errors') {
                const errorsValue = row.original.errors;
                if (!errorsValue || (typeof errorsValue === 'object' && Object.keys(errorsValue).length === 0)) {
                  return <span className="text-gray-400 text-xs">-</span>;
                }
                return <ErrorDisplay errors={errorsValue} variant="errors" />;
              }

              if (baseKey === 'invalid_codes') {
                const invalidCodesValue = row.original.invalid_codes;
                if (!invalidCodesValue || (typeof invalidCodesValue === 'object' && Object.keys(invalidCodesValue).length === 0)) {
                  return <span className="text-gray-400 text-xs">-</span>;
                }
                return <ErrorDisplay errors={invalidCodesValue} variant="invalid_codes" />;
              }

              if (hasActivityCategoryCodeRaw) {
                return (
                    <div className="flex items-center space-x-2">
                      <div>
                        {renderSingleValue(activityCategoryCodeRawValue)}
                        {renderSingleValue(activityCategoryIdValue, 'text-gray-500')}
                      </div>
                      <div>
                        {renderSingleValue(idValue, 'text-gray-500')}
                      </div>
                    </div>
                );
              }

              if (hasPathRaw) {
                return (
                    <div>
                        {renderSingleValue(pathRawValue)}
                        {renderSingleValue(pathValue, 'text-gray-500')}
                        {renderSingleValue(idValue, 'text-gray-500')}
                    </div>
                );
              }

              if (hasCodeRaw) {
                return (
                    <div>
                        {renderSingleValue(codeRawValue)}
                        {renderSingleValue(idValue, 'text-gray-500')}
                    </div>
                );
              }

              if (!hasRaw && !hasPlain) return null;

              if (!hasRaw) return renderSingleValue(plainValue);
              if (!hasPlain) return renderSingleValue(rawValue);

              // If values are the same, show only one.
              if (String(rawValue) === String(plainValue)) {
                return renderSingleValue(rawValue);
              }

              // Paired field: raw over processed, processed is gray
              return (
                  <div>
                      {renderSingleValue(rawValue)}
                      {renderSingleValue(plainValue, 'text-gray-500')}
                  </div>
              );
          },
          enableSorting: true,
          enableHiding: baseKey !== 'row_id',
      };
      
      // Enable text filtering on any field with a `_raw` version, name, external IDs, and special composite fields.
      // Filtering was "lost" because the condition was too specific and missed generic `_raw` fields.
      if (hasRaw || baseKey === 'name' || externalIdentCodes.includes(baseKey) || hasCodeRaw || hasPathRaw || hasActivityCategoryCodeRaw) {
          // For filtering, we must use the column that holds the raw text (e.g., `name_raw` instead of `name`).
          // The `id` is used by the fetcher to query the correct database column.
          columnDef.id = hasRaw ? rawKey : hasCodeRaw ? codeRawKey : hasPathRaw ? pathRawKey : hasActivityCategoryCodeRaw ? activityCategoryCodeRawKey : baseKey;
          columnDef.enableColumnFilter = true;
          // The `getCanFilter()` method on the column instance checks for the presence of a `filterFn`.
          // Even with manual filtering, this function needs to exist for the UI to show the filter input.
          // Since filtering is manual, the function itself is never called.
          columnDef.filterFn = placeholderFilterFn;
          columnDef.meta = {
              label: headerText,
              variant: 'text',
              placeholder: `Filter by ${baseKey.replace(/_/g, ' ')}...`,
              isPrimary: baseKey === 'name',
          };
      }
      
      if (['operation', 'state', 'action'].includes(baseKey)) {
          columnDef.enableColumnFilter = true;
          columnDef.filterFn = placeholderFilterFn;
          columnDef.meta = {
              label: headerText,
              variant: 'multiSelect',
              options: baseKey === 'operation' ? operationOptions : baseKey === 'state' ? stateOptions : actionOptions,
              isPrimary: true,
          };
      }

      if (['errors', 'invalid_codes'].includes(baseKey)) {
          columnDef.enableColumnFilter = true;
          columnDef.filterFn = placeholderFilterFn;
          columnDef.meta = {
              label: headerText,
              variant: 'select',
              options: [
                  { label: 'Has value', value: 'not_null' },
                  { label: 'Is empty', value: 'is_null' },
              ],
              isPrimary: true,
          };
      }
      
      return columnDef;
    });

    return finalColumns;
  }, [tableData?.data, externalIdentTypes]);

  const table = useReactTable({
    data: tableData?.data ?? [],
    columns,
    pageCount,
    state: {
      pagination,
      sorting,
      columnFilters,
      columnVisibility,
    },
    enableFilters: true,
    enableColumnFilters: true,
    enableRowSelection: true,
    onPaginationChange: setPagination,
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onColumnVisibilityChange: setColumnVisibility,
    getRowId: (row) => String(row.row_id),
    manualPagination: true,
    manualSorting: true,
    manualFiltering: true,
    // The following options were previously supplied by the useDataTable hook
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFacetedRowModel: getFacetedRowModel(),
    getFacetedUniqueValues: getFacetedUniqueValues(),
    getFacetedMinMaxValues: getFacetedMinMaxValues(),
  });

  const isLoading = isJobLoading || (isTableDataLoading && !tableData);

  // Check if error filter is active
  const isErrorFilterActive = React.useMemo(() => {
    const stateFilter = columnFilters.find(f => f.id === 'state');
    if (!stateFilter || !Array.isArray(stateFilter.value)) return false;
    return stateFilter.value.includes('error') && stateFilter.value.length === 1;
  }, [columnFilters]);

  // Toggle error-only filter
  const toggleErrorFilter = React.useCallback(() => {
    setColumnFilters(prev => {
      const stateFilterIndex = prev.findIndex(f => f.id === 'state');
      
      if (isErrorFilterActive) {
        // Remove the error filter
        return prev.filter(f => f.id !== 'state');
      } else {
        // Add error filter (replace any existing state filter)
        const newFilters = prev.filter(f => f.id !== 'state');
        return [...newFilters, { id: 'state', value: ['error'] }];
      }
    });
  }, [isErrorFilterActive]);

  if (jobError) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Failed to load import job details: {jobError.message}
      </div>
    );
  }

  if (isLoading) {
    const skeletonColumnCount = 7 + (externalIdentTypes?.length ?? 2);
    const skeletonFilterCount = 6 + (externalIdentTypes?.length ?? 2);
    return (
      <div className="space-y-4">
        <div>
          <div className="flex items-center space-x-2">
            <Link href="/import" className="text-2xl font-semibold text-gray-500 hover:underline">
              Import
            </Link>
            <ChevronRight className="h-6 w-6 text-gray-400" />
            <Link href="/import/jobs" className="text-2xl font-semibold text-gray-500 hover:underline">
              Jobs
            </Link>
            <ChevronRight className="h-6 w-6 text-gray-400" />
            <h1 className="text-2xl font-semibold">Data for Job: {jobSlug}</h1>
          </div>
          <Skeleton className="mt-1 h-5 w-1/2" />
        </div>
        <DataTableSkeleton
          columnCount={skeletonColumnCount}
          filterCount={skeletonFilterCount}
          rowCount={pagination.pageSize}
        />
      </div>
    );
  }

  if (!job) {
    return (
      <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-md text-yellow-800">
        Import job with slug &quot;{jobSlug}&quot; not found.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <div className="flex items-center space-x-2">
          <Link href="/import" className="text-2xl font-semibold text-gray-500 hover:underline">
            Import
          </Link>
          <ChevronRight className="h-6 w-6 text-gray-400" />
          <Link href="/import/jobs" className="text-2xl font-semibold text-gray-500 hover:underline">
            Jobs
          </Link>
          <ChevronRight className="h-6 w-6 text-gray-400" />
          <h1 className="text-2xl font-semibold">Data for Job: {job.id}</h1>
        </div>
        <p className="text-sm text-gray-500 mt-1">Description: {job.description ?? 'N/A'} | Table: {job.data_table_name}</p>
      </div>
      
      {tableError && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
          Failed to load table data: {tableError.message}
        </div>
      )}

      {columns.length > 0 &&
        <DataTable 
          table={table} 
          isValidating={isTableDataValidating}
          getRowClassName={(row: ImportJobDataRow) => {
            // Highlight rows with errors or invalid codes
            const hasErrors = row.errors && typeof row.errors === 'object' && Object.keys(row.errors).length > 0;
            const hasInvalidCodes = row.invalid_codes && typeof row.invalid_codes === 'object' && Object.keys(row.invalid_codes).length > 0;
            const state = row.state;
            
            if (state === 'error') {
              return 'bg-red-50/50 hover:bg-red-100/50';
            }
            if (hasErrors) {
              return 'bg-red-50/30 hover:bg-red-100/30';
            }
            if (hasInvalidCodes) {
              return 'bg-amber-50/30 hover:bg-amber-100/30';
            }
            return undefined;
          }}
        >
          <DataTableToolbar table={table}>
            <Button
              variant={isErrorFilterActive ? "default" : "outline"}
              size="sm"
              className={isErrorFilterActive 
                ? "h-8 bg-red-600 hover:bg-red-700 text-white" 
                : "h-8 border-dashed text-red-600 hover:bg-red-50 hover:text-red-700"
              }
              onClick={toggleErrorFilter}
            >
              <AlertTriangle className="mr-1 h-4 w-4" />
              {isErrorFilterActive ? "Showing Errors" : "Show Errors Only"}
            </Button>
          </DataTableToolbar>
        </DataTable>
      }
    </div>
  );
}
