"use client";

import React from "react";
import useSWR, { useSWRConfig } from 'swr';
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";
import { Tables } from '@/lib/database.types';
import { useDataTable } from "@/hooks/use-data-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { ColumnDef, PaginationState, SortingState } from "@tanstack/react-table";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { ChevronRight } from "lucide-react";

type ImportJob = Tables<"import_job"> & {
  import_definition: {
    name: string | null;
  } | null;
};
type ImportJobDataRow = { [key: string]: any };

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
      .from(tableName)
      .select('*', { count: 'exact' })
      .range(from, to);
    
    sortingParams.forEach(sort => {
      const [id, dir] = sort.split('.');
      if (id && dir) {
        queryBuilder = queryBuilder.order(id, { ascending: dir === 'asc' });
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

  const [pagination, setPagination] = React.useState<PaginationState>({
    pageIndex: 0,
    pageSize: 10,
  });

  const [sorting, setSorting] = React.useState<SortingState>([
    { id: "row_id", desc: false },
  ]);

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

    return `import-data/${tableName}?${params.toString()}`;
  }, [tableName, pagination, sorting]);


  const { data: tableData, error: tableError, isLoading: isTableDataLoading } = useSWR<{
    data: ImportJobDataRow[];
    count: number | null;
  }>(
    tableDataSWRKey,
    fetcher,
    { revalidateOnFocus: false }
  );

  React.useEffect(() => {
    if (!job?.id) return;

    const sseUrl = `/api/sse/import-jobs?ids=${job.id}`;
    const eventSource = new EventSource(sseUrl);

    eventSource.onmessage = (event) => {
      try {
        if (!event.data) return;
        const ssePayload = JSON.parse(event.data);
        if (ssePayload.type === "connection_established" || ssePayload.type === "heartbeat") return;

        // If the update is for our job, revalidate SWR caches
        if (ssePayload.import_job?.id === job.id) {
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log(`SSE: Job ${job.id} updated, revalidating data page.`);
          }
          mutate(`import-job/${jobSlug}`);
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
  }, [job?.id, jobSlug, tableDataSWRKey, mutate]);

  const pageCount = React.useMemo(() => {
    return tableData?.count != null
      ? Math.ceil(tableData.count / pagination.pageSize)
      : -1;
  }, [tableData?.count, pagination.pageSize]);

  const columns = React.useMemo<ColumnDef<ImportJobDataRow>[]>(() => {
    if (!tableData?.data || tableData.data.length === 0) return [];
    
    // Collect unique keys from all rows
    const allKeys = new Set<string>();
    tableData.data.forEach(row => {
      Object.keys(row).forEach(key => allKeys.add(key));
    });
    let keys = Array.from(allKeys);

    // Define preferred order
    const preferredOrder = ['row_id', 'operation', 'error', 'invalid_codes', 'action'];

    // Sort keys: preferred first in specified order, then others alphabetically
    keys.sort((a, b) => {
      const aIndex = preferredOrder.indexOf(a);
      const bIndex = preferredOrder.indexOf(b);
      const aPos = aIndex === -1 ? preferredOrder.length : aIndex;
      const bPos = bIndex === -1 ? preferredOrder.length : bIndex;
      if (aPos !== bPos) return aPos - bPos;
      return a.localeCompare(b);
    });

    return keys.map(key => ({
      id: key,
      accessorKey: key,
      header: ({ column }) => <DataTableColumnHeader column={column} title={key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())} />,
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
        return <div className="text-xs truncate" title={displayValue}>{displayValue}</div>;
      },
      enableSorting: true,
    }));
  }, [tableData]);

  const { table } = useDataTable({
    data: tableData?.data ?? [],
    columns,
    manualPagination: true,
    pageCount,
    state: {
      sorting,
      pagination,
    },
    onPaginationChange: setPagination,
    onSortingChange: setSorting,
    getRowId: (row) => String(row.row_id),
  });

  if (isJobLoading) {
    return <Spinner message={`Loading job details for ${jobSlug}...`} />;
  }

  if (jobError) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Failed to load import job details: {jobError.message}
      </div>
    );
  }

  if (!job) {
    return (
      <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-md text-yellow-800">
        Import job with slug "{jobSlug}" not found.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <div className="flex items-center space-x-2">
          <Link href="/import/jobs" className="text-2xl font-semibold text-gray-500 hover:underline">
            Import Jobs
          </Link>
          <ChevronRight className="h-6 w-6 text-gray-400" />
          <h1 className="text-2xl font-semibold">Imported Data for Job: {job.id}</h1>
        </div>
        <p className="text-sm text-gray-500 mt-1">Type: {job.import_definition?.name ?? 'N/A'} | Table: {job.data_table_name}</p>
      </div>

      {isTableDataLoading && <Spinner message={`Loading data from ${tableName}...`} />}
      
      {tableError && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
          Failed to load table data: {tableError.message}
        </div>
      )}

      {tableData?.data && (
        <DataTable table={table}>
          <DataTableToolbar table={table} />
        </DataTable>
      )}
    </div>
  );
}
