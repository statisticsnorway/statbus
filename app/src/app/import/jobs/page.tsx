"use client";

export const dynamic = 'force-dynamic';

import React, { useEffect, useMemo, useRef, useState } from "react";
import useSWR, { useSWRConfig } from 'swr';
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";
import { formatDuration } from "@/lib/utils";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { formatDistanceToNow } from "date-fns";
import { AlertCircle, CheckCircle, Clock, FileUp, FolderSearch, Hourglass, Loader, MoreHorizontal, ThumbsDown, ThumbsUp, Trash2 } from "lucide-react";
import { Tables } from '@/lib/database.types';
import { useDataTable } from "@/hooks/use-data-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { ColumnDef } from "@tanstack/react-table";
import { useQueryState, parseAsString, parseAsArrayOf, parseAsInteger } from 'nuqs';
import Link from "next/link";
import { Checkbox } from "@/components/ui/checkbox";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { DataTableActionBar, DataTableActionBarAction, DataTableActionBarSelection } from "@/components/data-table/data-table-action-bar";
import { Button } from "@/components/ui/button";
import { type ImportJobWithDetails as ImportJob } from "@/atoms/import";

const SWR_KEY_IMPORT_JOBS = "/api/import-jobs";

const formatDate = (dateString: string | null): string => {
  if (dateString === null) return 'N/A';
  if (dateString === 'infinity') return 'Present';
  try {
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'Invalid Date';
    return date.toLocaleDateString('nb-NO', {
      day: 'numeric', month: 'short', year: 'numeric'
    });
  } catch (e) {
    return dateString;
  }
};

const formatNumber = (num: number | null | undefined): string => {
  if (num === null || num === undefined) return "0";
  return num.toLocaleString('nb-NO');
};

const jobStatuses = [
  { value: "waiting_for_upload", label: "Waiting for Upload", icon: FileUp },
  { value: "upload_completed", label: "Uploaded", icon: Loader },
  { value: "preparing_data", label: "Preparing", icon: Loader },
  { value: "analysing_data", label: "Analyzing", icon: Hourglass },
  { value: "processing_data", label: "Processing", icon: Hourglass },
  { value: "waiting_for_review", label: "Review", icon: Clock },
  { value: "approved", label: "Approved", icon: ThumbsUp },
  { value: "finished", label: "Finished", icon: CheckCircle },
  { value: "rejected", label: "Rejected", icon: ThumbsDown },
] as const;

type JobStatusValue = (typeof jobStatuses)[number]["value"];
const jobStatusValues = jobStatuses.map(s => s.value);

// Custom nuqs parser for job statuses
const parseAsJobStatus = {
  parse: (value: string): JobStatusValue | null => {
    return (jobStatusValues as readonly string[]).includes(value) ? value as JobStatusValue : null;
  },
  serialize: (value: JobStatusValue): string => value,
};

const getUploadPathForJob = (job: ImportJob): string => {
  const mode = job.import_definition?.mode;
  if (!mode) return "/import/jobs";

  switch (mode) {
    case "legal_unit":
      return `/import/legal-units/upload/${job.slug}`;
    case "establishment_formal":
      return `/import/establishments/upload/${job.slug}`;
    case "establishment_informal":
      return `/import/establishments-without-legal-unit/upload/${job.slug}`;
    default:
      // For custom jobs, we don't have a specific upload page, link back to jobs list.
      return `/import/jobs`;
  }
};

const fetcher = async (key: string): Promise<{ data: ImportJob[], count: number | null }> => {
  const client = await getBrowserRestClient();
  if (!client) throw new Error("REST client not available");

  const [path, queryString] = key.split('?');
  
  if (path !== SWR_KEY_IMPORT_JOBS) {
    throw new Error(`Unrecognized SWR key pattern: ${key}`);
  }

  const searchParams = new URLSearchParams(queryString);
  const page = parseInt(searchParams.get('page') || '1', 10) - 1;
  const pageSize = parseInt(searchParams.get('perPage') || '10', 10);
  const sortParam = searchParams.get('sort');
  const description = searchParams.get('description');
  // nuqs stringifies arrays, so get all 'state' params
  const stateParams = searchParams.getAll('state').flatMap(s => s.split(','));
  const states = stateParams.filter((s): s is JobStatusValue => (jobStatusValues as readonly string[]).includes(s));
  
  const from = page * pageSize;
  const to = from + pageSize - 1;

  let queryBuilder = client
    .from("import_job")
    .select("*, import_definition(slug, name, mode, custom)", { count: 'exact' })
    .range(from, to);

  if (sortParam) {
    const [id, dir] = sortParam.split('.');
    if (id && dir) {
      queryBuilder = queryBuilder.order(id, { ascending: dir === 'asc' });
    }
  } else {
    queryBuilder = queryBuilder.order("created_at", { ascending: false });
  }

  if (description) {
    queryBuilder = queryBuilder.ilike('description', `%${description}%`);
  }
  if (states.length > 0) {
    queryBuilder = queryBuilder.in('state', states);
  }

  const { data, error, count } = await queryBuilder;
  if (error) {
    console.error("SWR Fetcher error (list jobs):", error);
    throw error;
  }
  return { data: data as ImportJob[], count };
};

export default function ImportJobsPage() {
  const { mutate } = useSWRConfig();
  const [errorToShow, setErrorToShow] = useState<string | null>(null);
  const eventSourceRef = useRef<EventSource | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  // Read state directly from URL to build the SWR key
  const [page] = useQueryState('page', parseAsInteger.withDefault(1));
  const [perPage] = useQueryState('perPage', parseAsInteger.withDefault(10));
  const [sort] = useQueryState('sort', parseAsString.withDefault(''));
  const [description] = useQueryState('description', parseAsString.withDefault(''));
  const [states] = useQueryState('state', parseAsArrayOf(parseAsJobStatus).withDefault([]));

  const swrKey = useMemo(() => {
    const params = new URLSearchParams();
    params.set('page', String(page));
    params.set('perPage', String(perPage));
    if (sort) params.set('sort', sort);
    if (description) params.set('description', description);
    // parseAsArrayOf uses a comma-separated string, so we pass that along.
    if (states.length > 0) params.set('state', states.join(','));

    return `${SWR_KEY_IMPORT_JOBS}?${params.toString()}`;
  }, [page, perPage, sort, description, states]);

  const { data, error: swrError, isLoading } = useSWR<{ data: ImportJob[], count: number | null }, Error>(
    swrKey,
    fetcher,
    { revalidateOnFocus: false, keepPreviousData: true }
  );

  const jobsData = data?.data ?? [];
  const totalJobs = data?.count ?? 0;

  useEffect(() => {
    if (isLoading || jobsData.length === 0) return;

    const jobIds = jobsData.map(job => job.id).join(',');
    const sseUrl = `/api/sse/import-jobs?ids=${jobIds}`;
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
        
        // Optimistically update SWR cache without revalidation
        mutate(swrKey, (currentData: { data: ImportJob[], count: number | null } | undefined) => {
          if (!currentData) return currentData;

          let newJobs = [...currentData.data];
          let newCount = currentData.count;

          if (ssePayload.verb === 'UPDATE') {
            const updatedJob = ssePayload.import_job;
            const index = newJobs.findIndex(job => job.id === updatedJob.id);
            if (index !== -1) {
              newJobs[index] = updatedJob;
            }
          } else if (ssePayload.verb === 'INSERT') {
            const newJob = ssePayload.import_job;
            if (!newJobs.some(job => job.id === newJob.id)) {
              newJobs.unshift(newJob); // Add to the top for visibility
              if (newCount !== null) newCount++;
            }
          } else if (ssePayload.verb === 'DELETE') {
            const jobToDelete = ssePayload.import_job;
            const preDeleteLength = newJobs.length;
            newJobs = newJobs.filter(job => job.id !== jobToDelete.id);
            if (newCount !== null && newJobs.length < preDeleteLength) {
                newCount--;
            }
          }

          return { data: newJobs, count: newCount };
        }, { revalidate: false });

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
  }, [isLoading, mutate, swrKey, jobsData]);

  // Ref to hold the current SWR key, allows handleDeleteJobs to be stable
  const swrKeyRef = useRef(swrKey);
  useEffect(() => {
    swrKeyRef.current = swrKey;
  }, [swrKey]);

  const handleDeleteJobs = React.useCallback(async (jobIds: number[]) => {
    if (!window.confirm(`Are you sure you want to delete ${jobIds.length} job(s)? This action cannot be undone.`)) {
      return;
    }
    setIsDeleting(true);
    try {
      const client = await getBrowserRestClient();
      const { error } = await client.from("import_job").delete().in("id", jobIds);
      if (error) throw error;
      mutate(swrKeyRef.current);
    } catch (err: any) {
      console.error("Failed to delete import jobs:", err);
      alert(`Error deleting jobs: ${err.message}`);
    } finally {
      setIsDeleting(false);
    }
  }, [mutate]);

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
      id: 'id',
      accessorKey: 'id',
      header: ({ column }) => <DataTableColumnHeader column={column} title="ID" />,
      cell: ({ row }) => <div className="text-xs">{row.original.id}</div>,
      enableSorting: true,
    },
    {
      id: 'description',
      accessorKey: 'description',
      header: ({ column }) => <DataTableColumnHeader column={column} title="Description" />,
      cell: ({ row }) => {
        const job = row.original;
        return <div className="font-medium">{job.description}</div>;
      },
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

        const badgeAndError = (
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

        const { total_rows } = job;

        const rowCountDisplay = total_rows !== null && total_rows !== undefined ? (
          <div className="text-xs text-gray-500 font-mono">
            {formatNumber(total_rows)} Rows
          </div>
        ) : null;

        let processingDetails = null;
        if (job.state === 'processing_data') {
          processingDetails = (
            <div className="text-xs text-gray-500">
              Processing data in batches...
            </div>
          );
        }

        const hasDetails = rowCountDisplay || processingDetails;

        return (
          <div>
            {job.state === 'waiting_for_upload' ? (
              <Link href={getUploadPathForJob(job)}>{badgeAndError}</Link>
            ) : (
              badgeAndError
            )}
            {hasDetails && (
              <div className="mt-1 space-y-0.5">
                {rowCountDisplay}
                {processingDetails}
              </div>
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
      id: 'analysed',
      header: 'Analysis',
      cell: ({ row }) => {
        const { total_rows, analysis_completed_pct, state, current_step_code, definition_snapshot } = row.original;
        if (total_rows === null || total_rows === undefined) {
          return <span className="text-xs text-gray-400">-</span>;
        }

        const showProgress = (state === 'analysing_data' || state === 'processing_data' || state === 'finished') &&
                             analysis_completed_pct !== null && analysis_completed_pct !== undefined;

        let stepDetails = null;
        if (state === 'analysing_data' && current_step_code && definition_snapshot?.import_step_list) {
          const analysisSteps = definition_snapshot.import_step_list.filter(s => s.analyse_procedure);
          const currentStepIndex = analysisSteps.findIndex(s => s.code === current_step_code);
          const totalAnalysisSteps = analysisSteps.length;

          if (currentStepIndex !== -1 && totalAnalysisSteps > 0) {
            stepDetails = (
              <div className="text-xs text-gray-500">
                Step {currentStepIndex + 1} of {totalAnalysisSteps} ({current_step_code})
              </div>
            );
          }
        }

        if (!stepDetails && !showProgress) {
          return <span className="text-xs text-gray-400">-</span>;
        }

        return (
          <div className="w-32 space-y-1">
            {stepDetails}
            {showProgress && (
              <div className="flex items-center space-x-2">
                <Progress value={analysis_completed_pct ?? 0} className="h-1.5 flex-grow" />
                <span className="text-xs text-gray-500 font-mono">{Math.round(analysis_completed_pct ?? 0)}%</span>
              </div>
            )}
          </div>
        );
      }
    },
    {
      id: 'analysis_speed',
      header: 'Analysis (r/s)',
      accessorKey: 'analysis_rows_per_sec',
      cell: ({ row }) => {
        const { analysis_rows_per_sec: speed, analysis_start_at, analysis_completed_pct, state } = row.original;

        const speedDisplay = speed ? <div className="text-xs font-mono">{Number(speed).toFixed(2)}</div> : <span className="text-xs text-gray-400">-</span>;

        // ETR for analysis is based on wall-clock time and percentage complete, as 'analysis_rows_per_sec' is not a live metric.
        if (state === 'analysing_data' && analysis_start_at && analysis_completed_pct && analysis_completed_pct > 0 && analysis_completed_pct < 100) {
          const startTime = new Date(analysis_start_at).getTime();
          const now = Date.now();
          const elapsedMilliseconds = now - startTime;

          if (elapsedMilliseconds > 1000) { // Only calculate if more than a second has passed
            const totalEstimatedMilliseconds = (elapsedMilliseconds / analysis_completed_pct) * 100;
            const remainingMilliseconds = totalEstimatedMilliseconds - elapsedMilliseconds;
            const remainingSeconds = remainingMilliseconds / 1000;
            const timeLeft = formatDuration(remainingSeconds);

            return (
              <div>
                {speedDisplay}
                {timeLeft && <div className="text-xs text-gray-500 font-mono" title="Estimated time remaining">~ {timeLeft}</div>}
              </div>
            );
          }
        }

        return speedDisplay;
      }
    },
    {
      id: 'processed',
      header: 'Processed',
      cell: ({ row }) => {
        const { imported_rows, total_rows, slug, import_completed_pct, state } = row.original;
        if (total_rows === null || total_rows === undefined) {
          return <span className="text-xs text-gray-400">-</span>;
        }

        const showProgress = (state === 'processing_data' || state === 'finished') &&
                             import_completed_pct !== null && import_completed_pct !== undefined;

        return (
          <div className="w-32">
            <Link href={`/import/jobs/${slug}/data`} className="underline">
              <div className="text-xs font-mono">{formatNumber(imported_rows)}/{formatNumber(total_rows)}</div>
            </Link>
            {showProgress && (
              <div className="mt-1 flex items-center space-x-2">
                <Progress value={import_completed_pct ?? 0} className="h-1.5 flex-grow" />
                <span className="text-xs text-gray-500 font-mono">{Math.round(import_completed_pct ?? 0)}%</span>
              </div>
            )}
          </div>
        );
      }
    },
    {
      id: 'processing_speed',
      header: 'Processing (r/s)',
      accessorKey: 'import_rows_per_sec',
      cell: ({ row }) => {
        const { import_rows_per_sec: speed, total_rows, imported_rows, state } = row.original;

        const speedDisplay = speed ? <div className="text-xs font-mono">{Number(speed).toFixed(2)}</div> : <span className="text-xs text-gray-400">-</span>;

        if (state !== 'processing_data' || !speed || speed <= 0 || !total_rows) {
          return speedDisplay;
        }

        const rowsLeft = total_rows - (imported_rows ?? 0);
        if (rowsLeft <= 0) return speedDisplay;

        const secondsLeft = rowsLeft / speed;
        const timeLeft = formatDuration(secondsLeft);

        return (
          <div>
            {speedDisplay}
            {timeLeft && <div className="text-xs text-gray-500 font-mono" title="Estimated time remaining">~ {timeLeft}</div>}
          </div>
        );
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
      cell: ({ row, table }) => {
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
              <DropdownMenuItem asChild>
                <Link href={`/import/jobs/${job.slug}/data`}>
                  <FolderSearch className="mr-2 h-4 w-4" />
                  View Imported Data
                </Link>
              </DropdownMenuItem>
              <DropdownMenuItem
                className="text-red-600"
                onClick={async () => {
                  await handleDeleteJobs([job.id]);
                  table.toggleAllRowsSelected(false);
                }}
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

  const pageCount = useMemo(() => {
    return perPage > 0 ? Math.ceil(totalJobs / perPage) : 0;
  }, [totalJobs, perPage]);

  const { table } = useDataTable({
    data: jobsData,
    columns,
    pageCount,
    manualPagination: true,
    manualSorting: true,
    manualFiltering: true,
    debounceMs: 500,
    initialState: {
      sorting: [{ id: "id", desc: true }],
    },
    getRowId: (row) => String(row.id),
  });

  const actionBar = (
    <DataTableActionBar table={table}>
      <DataTableActionBarSelection table={table} />
      <DataTableActionBarAction
        onClick={async () => {
          const selectedIds = table.getFilteredSelectedRowModel().rows.map(row => row.original.id);
          await handleDeleteJobs(selectedIds);
          table.toggleAllRowsSelected(false);
        }}
        isPending={isDeleting}
        tooltip="Delete selected jobs"
      >
        <Trash2 />
        Delete
      </DataTableActionBarAction>
    </DataTableActionBar>
  );

  if (isLoading && jobsData.length === 0) {
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
