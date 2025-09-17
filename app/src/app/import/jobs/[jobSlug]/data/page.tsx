"use client";

import React from "react";
import useSWR, { useSWRConfig } from 'swr';
import { getBrowserRestClient } from "@/context/RestClientStore";
import { DataTableSkeleton } from "@/components/data-table/data-table-skeleton";
import { Skeleton } from "@/components/ui/skeleton";
import { Tables } from '@/lib/database.types';
import { useDataTable } from "@/hooks/use-data-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { ColumnDef, PaginationState, SortingState, ColumnFiltersState } from "@tanstack/react-table";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { ChevronRight } from "lucide-react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useAtomValue } from "jotai";
import { externalIdentTypesAtom } from "@/atoms/base-data";
import { type ImportJobWithDetails as ImportJob } from "@/atoms/import";
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


export default function ImportJobDataPage({ params }: { params: Promise<{ jobSlug:string }> }) {
  const { jobSlug } = React.use(params);
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
    let keys = Array.from(allKeys);

    keys.sort((a, b) => {
      const aBase = a.replace(/_raw$/, '');
      const bBase = b.replace(/_raw$/, '');
      const aIsRaw = a.endsWith('_raw');

      if (aBase !== bBase) {
        const aIndex = preferredOrder.indexOf(aBase);
        const bIndex = preferredOrder.indexOf(bBase);
        const aPos = aIndex === -1 ? preferredOrder.length : aIndex;
        const bPos = bIndex === -1 ? preferredOrder.length : bIndex;
        if (aPos !== bPos) return aPos - bPos;
        return aBase.localeCompare(bBase);
      }
      return aIsRaw ? 1 : -1; // non-raw first
    });

    return keys.map(key => {
      const isRaw = key.endsWith('_raw');
      const baseKey = isRaw ? key.slice(0, -4) : key;
      const headerText = baseKey.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
      const isProcessed = !isRaw && allKeys.has(`${key}_raw`);

      const columnDef: ColumnDef<ImportJobDataRow> = {
        id: key,
        accessorKey: key,
        header: ({ column }) => <DataTableColumnHeader column={column} title={headerText} />,
        cell: ({ row }) => {
          const value = row.getValue(key);
          let displayValue;
          if (value === null) {
            displayValue = 'NULL';
          } else if (typeof value === 'object') {
            displayValue = JSON.stringify(value);
          } else {
            displayValue = String(value);
          }
          return <div className={`text-xs truncate ${isProcessed ? 'text-gray-500' : ''}`} title={displayValue}>{displayValue}</div>;
        },
        enableSorting: true,
      };
      
      if (baseKey === 'name' || externalIdentCodes.includes(baseKey)) {
        columnDef.enableColumnFilter = true;
        columnDef.meta = {
          label: isRaw ? `${headerText} (Raw)` : headerText,
          variant: 'text',
          placeholder: `Filter by ${baseKey.replace(/_/g, ' ')}...`
        };
      }
      
      if (['operation', 'state', 'action'].includes(key)) {
        columnDef.enableColumnFilter = true;
        columnDef.meta = {
          label: key.charAt(0).toUpperCase() + key.slice(1),
          variant: 'multiSelect',
          options: key === 'operation' ? operationOptions : key === 'state' ? stateOptions : actionOptions,
        };
      }

      if (['errors', 'invalid_codes'].includes(key)) {
        columnDef.enableColumnFilter = true;
        columnDef.meta = {
          label: key === 'errors' ? 'Errors' : 'Invalid Codes',
          variant: 'select',
          options: [
            { label: 'Has value', value: 'not_null' },
            { label: 'Is empty', value: 'is_null' },
          ],
        };
      }
      
      return columnDef;
    });
  }, [tableData?.data, externalIdentTypes]);

  const { table } = useDataTable({
    data: tableData?.data ?? [],
    columns,
    manualPagination: true,
    manualFiltering: true,
    debounceMs: 500,
    pageCount,
    state: {
      pagination,
      sorting,
      columnFilters,
    },
    onPaginationChange: setPagination,
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    getRowId: (row) => String(row.row_id),
  });

  const isLoading = isJobLoading || (isTableDataLoading && !tableData);

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
        <DataTable table={table} isValidating={isTableDataValidating}>
          <DataTableToolbar table={table} />
        </DataTable>
      }
    </div>
  );
}
