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
import { AlertCircle, CheckCircle, Clock, FileUp, Hourglass, Loader, MoreHorizontal, ThumbsDown, ThumbsUp, Trash2 } from "lucide-react";
import { Tables } from '@/lib/database.types';
import { useDataTable } from "@/hooks/use-data-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { ColumnDef } from "@tanstack/react-table";
import { useQueryState, parseAsString, parseAsArrayOf } from 'nuqs';
import Link from "next/link";
import { Checkbox } from "@/components/ui/checkbox";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { DataTableActionBar, DataTableActionBarAction, DataTableActionBarSelection } from "@/components/data-table/data-table-action-bar";
import { Button } from "@/components/ui/button";

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

const getUploadPathForJob = (job: ImportJob): string => {
  const slug = job.import_definition?.slug;
  if (!slug) return "/import/jobs";

  if (slug.startsWith("legal_unit")) {
    return `/import/legal-units/upload/${job.slug}`;
  }
  if (slug.startsWith("establishment_for_lu")) {
    return `/import/establishments/upload/${job.slug}`;
  }
  if (slug.startsWith("establishment_without_lu")) {
    return `/import/establishments-without-legal-unit/upload/${job.slug}`;
  }
  return `/import/jobs`;
};

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
  const [isDeleting, setIsDeleting] = useState(false);

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

  const handleDeleteJobs = async (jobIds: number[]) => {
    if (!window.confirm(`Are you sure you want to delete ${jobIds.length} job(s)? This action cannot be undone.`)) {
      return;
    }
    setIsDeleting(true);
    try {
      const client = await getBrowserRestClient();
      const { error } = await client.from("import_job").delete().in("id", jobIds);
      if (error) throw error;
      mutate(SWR_KEY_IMPORT_JOBS);
      table.toggleAllRowsSelected(false);
    } catch (err: any) {
      console.error("Failed to delete import jobs:", err);
      alert(`Error deleting jobs: ${err.message}`);
    } finally {
      setIsDeleting(false);
    }
  };

  const columns = useMemo<ColumnDef<ImportJob>[]>(() => [
    {
      id: "select",
      header: ({ table }) => (
        <Checkbox
          checked={table.getIsAllPageRowsSelected() || (table.getIsSomePageRowsSelected() && "indeterminate")}
          onCheckedChange={(value) => table.toggleAllPageRowsSelected(!!value)}
          aria-label="Select all"
        />
      ),
      cell: ({ row }) => (
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(value) => row.toggleSelected(!!value)}
          aria-label="Select row"
        />
      ),
      enableSorting: false,
      enableHiding: false,
    },
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
        const job = row.original;
        const status = jobStatuses.find(s => s.value === job.state);
        const statusBadge = (
          <Badge variant={job.state === 'finished' ? 'default' : job.state === 'rejected' ? 'destructive' : 'secondary'}
            className={job.state === 'finished' ? 'bg-green-600 text-white' : ''}
          >
            {status?.icon && <status.icon className="mr-2 h-4 w-4" />}
            {status?.label ?? job.state}
          </Badge>
        );

        const content = (
          <div className="flex items-center space-x-2">
            {statusBadge}
            {job.error && (
              <Dialog>
                <DialogTrigger asChild>
                  <button onClick={() => setErrorToShow(job.error)} className="text-red-500 hover:text-red-700" title="Show error details">
                    <AlertCircle className="h-4 w-4" />
                  </button>
                </DialogTrigger>
              </Dialog>
            )}
          </div>
        );

        if (job.state === 'waiting_for_upload') {
          return <Link href={getUploadPathForJob(job)}>{content}</Link>;
        }
        return content;
      },
      meta: {
        label: "Status",
        variant: "multiSelect",
        options: [...jobStatuses],
      },
      enableColumnFilter: true,
    },
    {
      id: 'rows',
      header: 'Rows',
      cell: ({ row }) => {
        const { imported_rows, total_rows } = row.original;
        if (total_rows === null || total_rows === undefined) return <span className="text-xs text-gray-400">-</span>;
        return <div className="text-xs">{imported_rows ?? 0} / {total_rows}</div>;
      }
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
      id: 'speed',
      header: 'Speed (rows/s)',
      accessorKey: 'import_rows_per_sec',
      cell: ({ row }) => {
        const speed = row.original.import_rows_per_sec;
        return speed ? <div className="text-xs">{Number(speed).toFixed(2)}</div> : <span className="text-xs text-gray-400">-</span>;
      }
    },
    {
      id: 'expires_at',
      header: ({ column }) => <DataTableColumnHeader column={column} title="Expires" />,
      accessorKey: 'expires_at',
      cell: ({ row }) => {
        const expires = row.original.expires_at;
        return expires ? <div className="text-xs text-gray-500">{formatDistanceToNow(new Date(expires), { addSuffix: true })}</div> : <span className="text-xs text-gray-400">-</span>;
      },
      enableSorting: true,
    },
    {
      id: "actions",
      cell: ({ row }) => {
        const job = row.original;
        return (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="h-8 w-8 p-0">
                <span className="sr-only">Open menu</span>
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem
                className="text-red-600"
                onClick={() => handleDeleteJobs([job.id])}
                disabled={isDeleting}
              >
                <Trash2 className="mr-2 h-4 w-4" />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        );
      },
    },
  ], [setErrorToShow, isDeleting, handleDeleteJobs]);

  const { table } = useDataTable({
    data: filteredJobs,
    columns,
    manualPagination: false,
    initialState: {
      sorting: [{ id: "expires_at", desc: true }],
    },
    getRowId: (row) => String(row.id),
  });

  const actionBar = (
    <DataTableActionBar table={table}>
      <DataTableActionBarSelection table={table} />
      <DataTableActionBarAction
        onClick={() => {
          const selectedIds = table.getFilteredSelectedRowModel().rows.map(row => row.original.id);
          handleDeleteJobs(selectedIds);
        }}
        isPending={isDeleting}
        tooltip="Delete selected jobs"
      >
        <Trash2 />
        Delete
      </DataTableActionBarAction>
    </DataTableActionBar>
  );

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
      <DataTable table={table} actionBar={actionBar}>
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
