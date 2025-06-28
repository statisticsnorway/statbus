"use client";

export const dynamic = 'force-dynamic';

import React, { useEffect, useMemo, useRef, useState } from "react";
import useSWR, { useSWRConfig } from 'swr';
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { formatDistanceToNow } from "date-fns";
import { AlertCircle, CheckCircle, Clock, FileUp, Hourglass, Loader, ThumbsDown, ThumbsUp } from "lucide-react";
import { Tables } from '@/lib/database.types';
import { useDataTable } from "@/hooks/use-data-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { ColumnDef } from "@tanstack/react-table";
import { useQueryState, parseAsString, parseAsArrayOf } from 'nuqs';

type ImportJob = Tables<"import_job"> & {
  import_definition: { slug: string; name: string; } | null;
};

const SWR_KEY_IMPORT_JOBS = "/api/import-jobs";

const jobStatuses = [
  { value: "waiting_for_upload", label: "Waiting for Upload", icon: FileUp },
  { value: "upload_completed", label: "Preparing", icon: Loader },
  { value: "preparing_data", label: "Preparing", icon: Loader },
  { value: "analysing_data", label: "Analyzing", icon: Hourglass },
  { value: "processing_data", label: "Processing", icon: Hourglass },
  { value: "waiting_for_review", label: "Review", icon: Clock },
  { value: "approved", label: "Approved", icon: ThumbsUp },
  { value: "finished", label: "Finished", icon: CheckCircle },
  { value: "rejected", label: "Rejected", icon: ThumbsDown },
] as const;

const fetcher = async (key: string): Promise<ImportJob[]> => {
  const client = await getBrowserRestClient();
  if (!client) throw new Error("REST client not available");

  if (key === SWR_KEY_IMPORT_JOBS) {
    const { data, error } = await client
      .from("import_job")
      .select("*, import_definition(slug, name)")
      .order("created_at", { ascending: false });
    if (error) {
      console.error("SWR Fetcher error (list jobs):", error);
      throw error;
    }
    return data as ImportJob[];
  }
  throw new Error(`Unrecognized SWR key pattern: ${key}`);
};

export default function ImportJobsPage() {
  const { data: allJobs = [], error: swrError, isLoading } = useSWR<ImportJob[], Error>(
    SWR_KEY_IMPORT_JOBS,
    fetcher,
    { revalidateOnFocus: false }
  );

  const { mutate } = useSWRConfig();
  const [errorToShow, setErrorToShow] = useState<string | null>(null);
  const eventSourceRef = useRef<EventSource | null>(null);

  const [description] = useQueryState('description', parseAsString.withDefault(''));
  const [states] = useQueryState('state', parseAsArrayOf(parseAsString).withDefault([]));

  const filteredJobs = useMemo(() => {
    return allJobs.filter(job => {
      const matchesDescription = description === '' || job.description?.toLowerCase().includes(description.toLowerCase());
      const matchesState = states.length === 0 || (job.state && states.includes(job.state));
      return matchesDescription && matchesState;
    });
  }, [allJobs, description, states]);

  useEffect(() => {
    if (isLoading) return;

    const sseUrl = `/api/sse/import-jobs`;
    const source = new EventSource(sseUrl);
    eventSourceRef.current = source;

    source.onmessage = (event) => {
      try {
        if (!event.data) return;
        const ssePayload = JSON.parse(event.data);
        if (ssePayload.type === "connection_established" || event.type === "heartbeat") return;

        if (!ssePayload.verb || !ssePayload.import_job) {
          console.error("Invalid SSE payload", ssePayload);
          return;
        }
        mutate(SWR_KEY_IMPORT_JOBS); // Re-fetch the whole list on any change
      } catch (error) {
        console.error("Error processing SSE message:", error);
      }
    };

    source.onerror = (error) => {
      console.error("SSE connection error:", error);
      source.close();
    };

    return () => {
      eventSourceRef.current?.close();
    };
  }, [isLoading, mutate]);

  const columns = useMemo<ColumnDef<ImportJob>[]>(() => [
    {
      id: 'description',
      accessorKey: 'description',
      header: ({ column }) => <DataTableColumnHeader column={column} title="Description" />,
      cell: ({ row }) => <div className="font-medium">{row.original.description}</div>,
      meta: {
        label: "Description",
        placeholder: "Filter descriptions...",
        variant: "text",
      },
      enableColumnFilter: true,
    },
    {
      id: 'state',
      accessorKey: 'state',
      header: ({ column }) => <DataTableColumnHeader column={column} title="Status" />,
      cell: ({ row }) => {
        const status = jobStatuses.find(s => s.value === row.original.state);
        return (
          <div className="flex items-center space-x-2">
            <Badge variant={row.original.state === 'finished' ? 'default' : row.original.state === 'rejected' ? 'destructive' : 'secondary'}
              className={row.original.state === 'finished' ? 'bg-green-600 text-white' : ''}
            >
              {status?.icon && <status.icon className="mr-2 h-4 w-4" />}
              {status?.label ?? row.original.state}
            </Badge>
            {row.original.error && (
              <Dialog>
                <DialogTrigger asChild>
                  <button onClick={() => setErrorToShow(row.original.error)} className="text-red-500 hover:text-red-700" title="Show error details">
                    <AlertCircle className="h-4 w-4" />
                  </button>
                </DialogTrigger>
              </Dialog>
            )}
          </div>
        );
      },
      meta: {
        label: "Status",
        variant: "multiSelect",
        options: [...jobStatuses],
      },
      enableColumnFilter: true,
    },
    {
      accessorKey: 'import_completed_pct',
      header: 'Progress',
      cell: ({ row }) => {
        const job = row.original;
        return job.state && ["preparing_data", "analysing_data", "processing_data"].includes(job.state) && job.import_completed_pct !== null ? (
          <div className="w-32">
            <Progress value={job.import_completed_pct ?? 0} className="h-2" />
            <span className="text-xs text-gray-500">{Math.round(job.import_completed_pct ?? 0)}%</span>
          </div>
        ) : job.state === "finished" ? (
          <span className="text-xs text-green-600">100%</span>
        ) : (
          <span className="text-xs text-gray-400">-</span>
        );
      }
    },
    {
      accessorKey: 'updated_at',
      header: ({ column }) => <DataTableColumnHeader column={column} title="Last Updated" />,
      cell: ({ row }) => <div className="text-xs text-gray-500">{formatDistanceToNow(new Date(row.original.updated_at), { addSuffix: true })}</div>,
      enableSorting: true,
    },
    {
      accessorKey: 'created_at',
      header: ({ column }) => <DataTableColumnHeader column={column} title="Created" />,
      cell: ({ row }) => <div className="text-xs text-gray-500">{formatDistanceToNow(new Date(row.original.created_at), { addSuffix: true })}</div>,
      enableSorting: true,
    },
  ], [setErrorToShow]);

  const { table } = useDataTable({
    data: filteredJobs,
    columns,
    manualPagination: false,
    initialState: {
      sorting: [{ id: "updated_at", desc: true }],
    },
    getRowId: (row) => String(row.id),
  });

  if (isLoading && !allJobs.length) {
    return <Spinner message="Loading import jobs..." />;
  }

  if (swrError) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Failed to load import jobs: {swrError.message}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Import Jobs</h1>
      <DataTable table={table}>
        <DataTableToolbar table={table} />
      </DataTable>
      
      <Dialog open={!!errorToShow} onOpenChange={(open) => !open && setErrorToShow(null)}>
        <DialogContent className="sm:max-w-[600px]">
          <DialogHeader>
            <DialogTitle>Import Job Error</DialogTitle>
            <DialogDescription>
              The following error occurred during the import process.
            </DialogDescription>
          </DialogHeader>
          <div className="mt-4 p-4 bg-red-50 border border-red-200 rounded-md text-sm text-red-800 overflow-auto max-h-[60vh]">
            <pre className="whitespace-pre-wrap break-words">{errorToShow}</pre>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
