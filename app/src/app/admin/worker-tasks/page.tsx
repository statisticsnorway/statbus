"use client";

export const dynamic = "force-dynamic";

import React, { useMemo, useCallback } from "react";
import { useSWRWithAuthRefresh, isJwtExpiredError, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";
import { Badge } from "@/components/ui/badge";
import { formatDistanceToNow } from "date-fns";
import { Tables } from "@/lib/database.types";
import { useDataTable } from "@/hooks/use-data-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableToolbar } from "@/components/data-table/data-table-toolbar";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { ColumnDef } from "@tanstack/react-table";
import { useQueryState, parseAsString, parseAsArrayOf, parseAsInteger } from "nuqs";
import { COMMAND_LABELS } from "@/atoms/worker_status";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { RefreshCw, ChevronRight } from "lucide-react";
import { useSWRConfig } from "swr";

type WorkerTask = Tables<"worker_task">;

const SWR_KEY = "/api/worker-tasks";

const taskStates = [
  { value: "pending", label: "Pending" },
  { value: "processing", label: "Processing" },
  { value: "waiting", label: "Waiting" },
  { value: "completed", label: "Completed" },
  { value: "failed", label: "Failed" },
] as const;

type TaskStateValue = (typeof taskStates)[number]["value"];
const taskStateValues = taskStates.map((s) => s.value);

const parseAsTaskState = {
  parse: (value: string): TaskStateValue | null => {
    return (taskStateValues as readonly string[]).includes(value)
      ? (value as TaskStateValue)
      : null;
  },
  serialize: (value: TaskStateValue): string => value,
};

const queues = [
  { value: "analytics", label: "Analytics" },
  { value: "import", label: "Import" },
  { value: "maintenance", label: "Maintenance" },
] as const;

type QueueValue = (typeof queues)[number]["value"];
const queueValues = queues.map((q) => q.value);

const parseAsQueue = {
  parse: (value: string): QueueValue | null => {
    return (queueValues as readonly string[]).includes(value)
      ? (value as QueueValue)
      : null;
  },
  serialize: (value: QueueValue): string => value,
};

const stateColors: Record<string, string> = {
  pending: "bg-yellow-100 text-yellow-800",
  processing: "bg-blue-100 text-blue-800",
  waiting: "bg-purple-100 text-purple-800",
  completed: "bg-green-100 text-green-800",
  failed: "bg-red-100 text-red-800",
};

const formatDurationMs = (ms: number | null): string => {
  if (ms === null || ms === undefined) return "-";
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  const minutes = Math.floor(ms / 60000);
  const seconds = ((ms % 60000) / 1000).toFixed(0);
  return `${minutes}m${seconds}s`;
};

const formatUnitCounts = (task: WorkerTask): string | null => {
  const p = task.payload as Record<string, unknown> | null;
  if (!p) return null;
  const parts: string[] = [];
  if (p.affected_establishment_count)
    parts.push(`${p.affected_establishment_count} est`);
  if (p.affected_legal_unit_count)
    parts.push(`${p.affected_legal_unit_count} lu`);
  if (p.affected_enterprise_count)
    parts.push(`${p.affected_enterprise_count} en`);
  if (p.affected_power_group_count)
    parts.push(`${p.affected_power_group_count} pg`);
  return parts.length > 0 ? parts.join(", ") : null;
};

const fetcher = async (
  key: string
): Promise<{ data: WorkerTask[]; count: number | null }> => {
  const client = await getBrowserRestClient();
  if (!client) throw new Error("REST client not available");

  const [path, queryString] = key.split("?");

  if (path !== SWR_KEY) {
    throw new Error(`Unrecognized SWR key pattern: ${key}`);
  }

  const searchParams = new URLSearchParams(queryString);
  const page = parseInt(searchParams.get("page") || "1", 10) - 1;
  const pageSize = parseInt(searchParams.get("perPage") || "50", 10);
  const sortParam = searchParams.get("sort");
  const stateParams = searchParams
    .getAll("state")
    .flatMap((s) => s.split(","));
  const states = stateParams.filter((s): s is TaskStateValue =>
    (taskStateValues as readonly string[]).includes(s)
  );
  const queueParams = searchParams
    .getAll("queue")
    .flatMap((s) => s.split(","));
  const queueFilters = queueParams.filter((q): q is QueueValue =>
    (queueValues as readonly string[]).includes(q)
  );
  const command = searchParams.get("command");
  const parentId = searchParams.get("parentId");

  const from = page * pageSize;
  const to = from + pageSize - 1;

  let queryBuilder = client
    .from("worker_task")
    .select("*", { count: "exact" })
    .range(from, to);

  if (sortParam) {
    const [id, dir] = sortParam.split(".");
    if (id && dir) {
      queryBuilder = queryBuilder.order(id, {
        ascending: dir === "asc",
        nullsFirst: false,
      });
    }
  } else {
    queryBuilder = queryBuilder.order("id", { ascending: false });
  }

  // Filter by parent: top-level (null parent) or children of a specific task
  if (parentId && parseInt(parentId, 10) > 0) {
    queryBuilder = queryBuilder.eq("parent_id", parseInt(parentId, 10));
  } else {
    queryBuilder = queryBuilder.is("parent_id", null);
  }

  if (states.length > 0) {
    queryBuilder = queryBuilder.in("state", states);
  }
  if (queueFilters.length > 0) {
    queryBuilder = queryBuilder.in("queue", queueFilters);
  }
  if (command) {
    queryBuilder = queryBuilder.ilike("command", `%${command}%`);
  }

  const { data, error, count } = await queryBuilder;
  if (error) {
    console.error("SWR Fetcher error (worker tasks):", error);
    if (isJwtExpiredError(error)) throw new JwtExpiredError();
    throw error;
  }
  return { data: data as WorkerTask[], count };
};

/** Fetch a single task by ID (for breadcrumb parent info). */
const fetchParentTask = async (
  parentId: number
): Promise<WorkerTask | null> => {
  const client = await getBrowserRestClient();
  if (!client) return null;
  const { data, error } = await client
    .from("worker_task")
    .select("*")
    .eq("id", parentId)
    .single();
  if (error) return null;
  return data as WorkerTask;
};

export default function WorkerTasksPage() {
  const { mutate } = useSWRConfig();

  const [page, setPage] = useQueryState("page", parseAsInteger.withDefault(1));
  const [perPage] = useQueryState("perPage", parseAsInteger.withDefault(50));
  const [sort] = useQueryState("sort", parseAsString.withDefault(""));
  const [states] = useQueryState(
    "state",
    parseAsArrayOf(parseAsTaskState).withDefault([])
  );
  const [queueFilters] = useQueryState(
    "queue",
    parseAsArrayOf(parseAsQueue).withDefault([])
  );
  const [command] = useQueryState("command", parseAsString.withDefault(""));
  const [parentId, setParentId] = useQueryState("parentId", parseAsInteger);

  const isDrilledIn = parentId !== null && parentId > 0;

  const swrKey = useMemo(() => {
    const params = new URLSearchParams();
    params.set("page", String(page));
    params.set("perPage", String(perPage));
    if (sort) params.set("sort", sort);
    if (states.length > 0) params.set("state", states.join(","));
    if (queueFilters.length > 0) params.set("queue", queueFilters.join(","));
    if (command) params.set("command", command);
    if (isDrilledIn) params.set("parentId", String(parentId));
    return `${SWR_KEY}?${params.toString()}`;
  }, [page, perPage, sort, states, queueFilters, command, parentId, isDrilledIn]);

  const {
    data,
    error: swrError,
    isLoading,
    isValidating,
  } = useSWRWithAuthRefresh<{ data: WorkerTask[]; count: number | null }, Error>(
    swrKey,
    fetcher,
    { revalidateOnFocus: false, keepPreviousData: true, refreshInterval: 5000 },
    "WorkerTasksPage:tasks"
  );

  // Fetch parent task info for breadcrumb when drilled in
  const { data: parentTask } = useSWRWithAuthRefresh<WorkerTask | null, Error>(
    isDrilledIn ? `${SWR_KEY}/parent/${parentId}` : null,
    isDrilledIn ? () => fetchParentTask(parentId!) : null,
    { revalidateOnFocus: false },
    "WorkerTasksPage:parent"
  );

  const tasksData = data?.data ?? [];
  const totalTasks = data?.count ?? 0;

  const handleDrillIn = useCallback(
    async (task: WorkerTask) => {
      if (task.child_mode && task.id) {
        await setParentId(task.id);
        await setPage(1);
      }
    },
    [setParentId, setPage]
  );

  const handleDrillOut = useCallback(async () => {
    await setParentId(null);
    await setPage(1);
  }, [setParentId, setPage]);

  const columns = useMemo<ColumnDef<WorkerTask>[]>(
    () => [
      {
        id: "id",
        accessorKey: "id",
        minSize: 60,
        header: ({ column }) => (
          <DataTableColumnHeader column={column} title="ID" />
        ),
        cell: ({ row }) => (
          <div className="text-xs font-mono">{row.original.id}</div>
        ),
        enableSorting: true,
      },
      {
        id: "command",
        accessorKey: "command",
        minSize: 200,
        header: ({ column }) => (
          <DataTableColumnHeader column={column} title="Command" />
        ),
        cell: ({ row }) => {
          const task = row.original;
          const label =
            COMMAND_LABELS[task.command ?? ""] ?? task.command;
          const hasChildren = !!task.child_mode;
          return (
            <div className="flex items-center">
              <div className="flex-1">
                <div className="text-sm font-medium">{label}</div>
                {task.command_description && label !== task.command && (
                  <div className="text-xs text-gray-500 truncate max-w-[300px]">
                    {task.command}
                  </div>
                )}
              </div>
              {hasChildren && !isDrilledIn && (
                <ChevronRight className="h-4 w-4 text-gray-400 ml-2 flex-shrink-0" />
              )}
            </div>
          );
        },
        meta: {
          label: "Command",
          placeholder: "Filter commands...",
          variant: "text" as const,
        },
        enableColumnFilter: true,
      },
      {
        id: "queue",
        accessorKey: "queue",
        minSize: 100,
        header: ({ column }) => (
          <DataTableColumnHeader column={column} title="Queue" />
        ),
        cell: ({ row }) => {
          const queue = row.original.queue;
          return queue ? (
            <Badge variant="outline" className="text-xs">
              {queue}
            </Badge>
          ) : (
            <span className="text-xs text-gray-400">-</span>
          );
        },
        meta: {
          label: "Queue",
          variant: "multiSelect" as const,
          options: [...queues],
        },
        enableColumnFilter: true,
      },
      {
        id: "state",
        accessorKey: "state",
        minSize: 100,
        header: ({ column }) => (
          <DataTableColumnHeader column={column} title="State" />
        ),
        cell: ({ row }) => {
          const state = row.original.state ?? "";
          const colorClass = stateColors[state] ?? "bg-gray-100 text-gray-800";
          return (
            <Badge variant="secondary" className={colorClass}>
              {state}
            </Badge>
          );
        },
        meta: {
          label: "State",
          variant: "multiSelect" as const,
          options: [...taskStates],
        },
        enableColumnFilter: true,
      },
      {
        id: "child_mode",
        accessorKey: "child_mode",
        minSize: 80,
        header: "Children",
        cell: ({ row }) => {
          const mode = row.original.child_mode;
          return mode ? (
            <Badge variant="outline" className="text-xs">
              {mode}
            </Badge>
          ) : (
            <span className="text-xs text-gray-400">leaf</span>
          );
        },
      },
      {
        id: "duration_ms",
        accessorKey: "duration_ms",
        minSize: 80,
        header: ({ column }) => (
          <DataTableColumnHeader column={column} title="Duration" />
        ),
        cell: ({ row }) => (
          <div className="text-xs font-mono">
            {formatDurationMs(row.original.duration_ms)}
          </div>
        ),
        enableSorting: true,
      },
      {
        id: "units",
        header: "Units",
        minSize: 120,
        cell: ({ row }) => {
          const counts = formatUnitCounts(row.original);
          return counts ? (
            <div className="text-xs font-mono">{counts}</div>
          ) : (
            <span className="text-xs text-gray-400">-</span>
          );
        },
      },
      {
        id: "created_at",
        accessorKey: "created_at",
        minSize: 100,
        header: ({ column }) => (
          <DataTableColumnHeader column={column} title="Created" />
        ),
        cell: ({ row }) => {
          const created = row.original.created_at;
          return created ? (
            <div className="text-xs text-gray-500 whitespace-nowrap">
              {formatDistanceToNow(new Date(created), { addSuffix: true })}
            </div>
          ) : (
            <span className="text-xs text-gray-400">-</span>
          );
        },
        enableSorting: true,
      },
      {
        id: "error",
        accessorKey: "error",
        minSize: 80,
        header: "Error",
        cell: ({ row }) => {
          const error = row.original.error;
          if (!error) return <span className="text-xs text-gray-400">-</span>;
          return (
            <Dialog>
              <DialogTrigger asChild>
                <button className="text-xs text-red-600 hover:text-red-800 truncate max-w-[150px] block text-left">
                  {error.split("\n")[0]}
                </button>
              </DialogTrigger>
              <DialogContent className="sm:max-w-[600px] max-h-[80vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle>Task Error (ID: {row.original.id})</DialogTitle>
                </DialogHeader>
                <pre className="text-sm whitespace-pre-wrap bg-gray-50 p-4 rounded border">
                  {error}
                </pre>
              </DialogContent>
            </Dialog>
          );
        },
      },
    ],
    [isDrilledIn]
  );

  const pageCount = useMemo(() => {
    return perPage > 0 ? Math.ceil(totalTasks / perPage) : 0;
  }, [totalTasks, perPage]);

  const { table } = useDataTable({
    data: tasksData,
    columns,
    pageCount,
    manualPagination: true,
    manualSorting: true,
    manualFiltering: true,
    debounceMs: 500,
    initialState: {
      sorting: [{ id: "id", desc: true }],
      columnVisibility: {
        // In top-level view: show child_mode, hide queue (less useful)
        // In drilled-in view: hide child_mode (all same parent), show queue
        child_mode: !isDrilledIn,
        queue: isDrilledIn,
      },
      pagination: {
        pageSize: 50,
        pageIndex: 0,
      },
    },
    getRowId: (row) => String(row.id),
  });

  if (isLoading && tasksData.length === 0) {
    return <Spinner message="Loading worker tasks..." />;
  }

  if (swrError) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md text-red-700">
        Failed to load worker tasks: {swrError.message}
      </div>
    );
  }

  const parentLabel = parentTask
    ? (COMMAND_LABELS[parentTask.command ?? ""] ?? parentTask.command)
    : `Task #${parentId}`;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Worker Tasks</h1>
        <Button
          variant="outline"
          size="sm"
          onClick={() => mutate(swrKey)}
          disabled={isValidating}
        >
          <RefreshCw
            className={`h-4 w-4 mr-2 ${isValidating ? "animate-spin" : ""}`}
          />
          Refresh
        </Button>
      </div>

      {isDrilledIn && (
        <>
          {/* Breadcrumb */}
          <nav className="flex items-center text-sm text-gray-500">
            <button
              onClick={handleDrillOut}
              className="text-blue-600 hover:text-blue-800 hover:underline"
            >
              All Tasks
            </button>
            <ChevronRight className="h-4 w-4 mx-1 text-gray-400" />
            <span className="text-gray-900 font-medium">
              {parentLabel} #{parentId}
            </span>
          </nav>

          {/* Parent summary card */}
          {parentTask && (
            <div className="flex items-center gap-4 rounded-lg border bg-gray-50 px-4 py-3 text-sm">
              <div>
                <span className="font-medium">{parentLabel}</span>
                <span className="text-gray-500 ml-1">#{parentTask.id}</span>
              </div>
              <Badge
                variant="secondary"
                className={stateColors[parentTask.state ?? ""] ?? "bg-gray-100 text-gray-800"}
              >
                {parentTask.state}
              </Badge>
              <span className="font-mono text-xs text-gray-600">
                {formatDurationMs(parentTask.duration_ms)}
              </span>
              {formatUnitCounts(parentTask) && (
                <span className="font-mono text-xs text-gray-600">
                  {formatUnitCounts(parentTask)}
                </span>
              )}
            </div>
          )}
        </>
      )}

      <DataTable
        table={table}
        isValidating={isValidating}
        onRowClick={!isDrilledIn ? handleDrillIn : undefined}
        getRowClassName={(task) =>
          !isDrilledIn && task.child_mode ? "hover:bg-gray-50" : undefined
        }
      >
        <DataTableToolbar table={table} />
      </DataTable>
    </div>
  );
}
