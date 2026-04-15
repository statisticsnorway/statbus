"use client";

import { useCallback, useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { logger } from "@/lib/client-logger";
import { pendingUpgradeStatusAtom } from "@/atoms/upgrade-status";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import {
  ArrowDownToLine,
  Calendar,
  CheckCircle2,
  ChevronDown,
  Clock,
  Database,
  Loader2,
  RotateCcw,
  SkipForward,
  XCircle,
} from "lucide-react";

type UpgradeState =
  | "available"
  | "scheduled"
  | "in_progress"
  | "completed"
  | "failed"
  | "rolled_back"
  | "dismissed"
  | "skipped"
  | "superseded";

interface Upgrade {
  id: number;
  commit_sha: string;
  committed_at: string;
  topological_order: number | null;
  tags: string[];
  release_status: 'commit' | 'prerelease' | 'release';
  display_name: string;
  display_state: string;
  state: UpgradeState;
  summary: string;
  changes: string | null;
  release_url: string | null;
  has_migrations: boolean;
  from_version: string | null;
  scheduled_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  error: string | null;
  progress_log: string | null;
  rolled_back_at: string | null;
  docker_images_ready: boolean;
  release_builds_ready: boolean;
  skipped_at: string | null;
  dismissed_at: string | null;
  superseded_at: string | null;
  artifacts_ready: boolean;
  docker_images_downloaded: boolean;
  backup_path: string | null;
}

interface SystemInfo {
  key: string;
  value: string;
}

function StateBadge({ state, label }: { state: UpgradeState; label: string }) {
  // Label comes from PostgREST's public.display_state(upgrade) so the UI
  // doesn't duplicate the enum → human-readable mapping. The className
  // per state stays in the UI since it's styling, not presentation.
  const classes: Record<UpgradeState, string> = {
    available:   "bg-blue-100 text-blue-800",
    scheduled:   "bg-yellow-100 text-yellow-800",
    in_progress: "bg-purple-100 text-purple-800",
    completed:   "bg-green-100 text-green-800",
    failed:      "bg-red-100 text-red-800",
    rolled_back: "bg-orange-100 text-orange-800",
    dismissed:   "bg-gray-100 text-gray-700",
    skipped:     "bg-gray-100 text-gray-600",
    superseded:  "bg-gray-100 text-gray-500",
  };
  return <Badge className={classes[state]}>{label}</Badge>;
}

const fetcher = async (url: string) => {
  const resp = await fetch(url, {
    headers: { Accept: "application/json" },
    credentials: "include",
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
};

async function patchUpgrade(
  id: number,
  body: Record<string, unknown>,
): Promise<void> {
  const resp = await fetch(`/rest/upgrade?id=eq.${id}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    credentials: "include",
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`PATCH failed: ${text}`);
  }
}

export default function UpgradesPage() {
  const [hasActiveUpgradeForPolling, setHasActiveUpgradeForPolling] = useState(false);
  const {
    data: upgrades,
    error,
    mutate,
  } = useSWR<Upgrade[]>(
    // display_name + display_state are PostgREST computed columns (functions
    // taking the row type) — must be listed explicitly in select; select=*
    // only covers real + GENERATED columns.
    "/rest/upgrade?select=*,display_name,display_state&order=topological_order.desc.nullslast,committed_at.desc&limit=20",
    fetcher,
    {
      // Poll fast (3s) when an upgrade is active, slow (30s) otherwise.
      refreshInterval: hasActiveUpgradeForPolling ? 3000 : 30000,
      revalidateOnFocus: true,
      onSuccess: (data) => {
        setHasActiveUpgradeForPolling(
          data?.some(u => u.started_at && !u.completed_at && !u.error && !u.rolled_back_at) ?? false
        );
      },
    },
  );
  const { data: systemInfo } = useSWR<SystemInfo[]>(
    "/rest/system_info",
    fetcher,
  );
  const [acting, setActing] = useState<number | null>(null);
  const [checking, setChecking] = useState(false);

  // Refresh the upgrade list when SSE delivers an upgrade_changed event.
  // The pendingUpgradeStatusAtom is already refreshed by SSEConnectionManager.
  const upgradeStatus = useAtomValue(pendingUpgradeStatusAtom);
  useGuardedEffect(() => {
    mutate();
  }, [upgradeStatus, mutate], 'UpgradesPage:sse-refresh');

  const channel =
    systemInfo?.find((s) => s.key === "upgrade_channel")?.value ?? "stable";
  const lastDiscoverAt =
    systemInfo?.find((s) => s.key === "upgrade_last_discover_at")?.value;
  const diskFreeGB = systemInfo?.find((s) => s.key === "disk_free_gb")?.value;
  const diskFree = diskFreeGB ? parseInt(diskFreeGB, 10) : null;

  const [actionError, setActionError] = useState<string | null>(null);

  // Detect when an upgrade takes the app down — show the maintenance page inline.
  const hasActiveUpgrade = upgrades?.some((u) => {
    const s = u.state;
    return s === "in_progress" || s === "scheduled";
  });
  const showMaintenanceView = error && hasActiveUpgrade;

  const act = useCallback(
    async (id: number, body: Record<string, unknown>) => {
      setActing(id);
      setActionError(null);
      try {
        await patchUpgrade(id, body);
        await mutate();
      } catch (err) {
        setActionError(err instanceof Error ? err.message : String(err));
      } finally {
        setActing(null);
      }
    },
    [mutate],
  );

  // When the API goes down during an active upgrade, redirect to the
  // maintenance page with a return URL. The maintenance page shows live
  // progress and redirects back when the app is healthy again.
  if (showMaintenanceView && typeof window !== "undefined") {
    const returnPath = encodeURIComponent(window.location.pathname);
    const activeUpgradeRow = upgrades?.find(
      (u) => u.state === "in_progress" || u.state === "scheduled",
    );
    logger.info("UpgradesPage", "Redirecting to maintenance.html", {
      reason: error ? `fetch failed: ${error.message}` : "active upgrade detected",
      activeUpgrade: activeUpgradeRow
        ? { commit_sha: activeUpgradeRow.commit_sha, state: activeUpgradeRow.state }
        : null,
    });
    window.location.href = `/maintenance.html?return=${returnPath}`;
  }

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col py-8 md:py-12">
      <h1 className="text-center mb-3 text-xl lg:text-2xl">
        Software Upgrades
      </h1>
      <p className="mb-8 text-center text-muted-foreground">
        Manage StatBus software updates
      </p>

      {/* Status header */}
      <div className="mb-8 flex flex-wrap items-center justify-center gap-4 text-sm text-muted-foreground">
        <span>
          Channel: <strong className="text-foreground">{channel}</strong>
        </span>
        {lastDiscoverAt && (
          <span>
            Last checked:{" "}
            <strong className="text-foreground">
              {new Date(lastDiscoverAt).toLocaleString()}
            </strong>
          </span>
        )}
        {diskFree !== null && diskFree > 10 && (
          <span>Disk: <strong className="text-foreground">{diskFree}G free</strong></span>
        )}
        {diskFree !== null && diskFree <= 10 && diskFree > 5 && (
          <Badge className="bg-yellow-100 text-yellow-800">Low disk: {diskFree}G free</Badge>
        )}
        {diskFree !== null && diskFree <= 5 && (
          <Badge className="bg-red-100 text-red-800">Disk critical: {diskFree}G free — contact IT</Badge>
        )}
        <Button
          size="sm"
          variant="outline"
          disabled={checking}
          onClick={async () => {
            setChecking(true);
            try {
              await fetch('/rest/rpc/upgrade_request_check', {
                method: 'POST',
                credentials: 'include',
              });
              await mutate();
            } finally {
              setChecking(false);
            }
          }}
        >
          {checking ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" /> : <RotateCcw className="mr-1.5 h-3.5 w-3.5" />}
          {checking ? "Checking..." : "Schedule check"}
        </Button>
      </div>

      {error && (
        <Card className="mb-4 border-red-200 bg-red-50">
          <CardContent className="pt-6">
            <p className="text-red-800">
              Failed to load upgrades: {error.message}
            </p>
          </CardContent>
        </Card>
      )}

      {actionError && (
        <Card className="mb-4 border-red-200 bg-red-50">
          <CardContent className="pt-6">
            <p className="text-red-800">
              Action failed: {actionError}
            </p>
          </CardContent>
        </Card>
      )}

      {!upgrades && !error && (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      )}

      {upgrades && upgrades.length === 0 && (
        <Card>
          <CardContent className="pt-6 text-center text-muted-foreground">
            No upgrades discovered yet. The upgrade service will check
            periodically.
          </CardContent>
        </Card>
      )}

      {upgrades && upgrades.length > 0 && (() => {
        // Categorize upgrades
        const actionable: Upgrade[] = []; // in_progress, scheduled, failed, rolled_back
        const available: Upgrade[] = [];
        const history: Upgrade[] = [];

        for (const u of upgrades) {
          const s = u.state;
          if (
            s === "completed" ||
            s === "skipped" ||
            s === "dismissed" ||
            s === "superseded"
          ) {
            history.push(u);
          } else if (s === "available") {
            available.push(u);
          } else {
            // in_progress, scheduled, failed, rolled_back — all stay actionable.
            // Failed/rolled_back remain visible on the main page so operators
            // see what went wrong without expanding history; clicking Dismiss
            // sets state='dismissed' and moves them to history.
            actionable.push(u);
          }
        }

        // When an upgrade is scheduled or in-progress, hide available entries entirely.
        // The user only needs to see the active upgrade, not other options.
        const hasActiveAction = actionable.some((u) => {
          const s = u.state;
          return s === "scheduled" || s === "in_progress";
        });

        // Only show the latest available prominently. Older ones go behind a collapsible.
        const latestAvailable = !hasActiveAction && available.length > 0 ? available[0] : null;
        const olderAvailable = !hasActiveAction ? available.slice(1) : [];

        // Migrations badge propagation: if ANY available release has migrations,
        // the latest must show it (upgrading to latest runs all intermediate migrations).
        const anyAvailableHasMigrations = available.some((u) => u.has_migrations);
        const latestWithMigrations = latestAvailable && anyAvailableHasMigrations
          ? { ...latestAvailable, has_migrations: true }
          : latestAvailable;

        // Only allow restoring skipped versions newer than the latest completed upgrade.
        const latestCompleted = history.find(u => u.state === 'completed');

        // The currently-running row stays visible at all times so operators
        // always have an anchor for "what version am I on right now?". The rest
        // of history (older completions, superseded, skipped, failed) stays in
        // the collapsible.
        const historyRest = latestCompleted
          ? history.filter(u => u.id !== latestCompleted.id)
          : history;

        const renderCard = (u: Upgrade) => {
          const status = u.state;
          const canRestore = latestCompleted
            ? (u.topological_order ?? 0) > (latestCompleted.topological_order ?? 0) || u.committed_at > latestCompleted.committed_at
            : true;
          return (
            <UpgradeCard
              key={u.id}
              upgrade={u}
              status={status}
              acting={acting === u.id}
              canRestore={canRestore}
              onScheduleNow={async () => {
                await act(u.id, {
                  state: "scheduled",
                  scheduled_at: new Date().toISOString(),
                });
                window.location.href = `/maintenance.html?return=${encodeURIComponent(window.location.pathname)}`;
              }}
              onUnschedule={() =>
                act(u.id, { state: "available", scheduled_at: null })
              }
              onRefetch={() => {}}
              onSkip={() =>
                // Skip is for available upgrades. State transitions
                // available → skipped.
                act(u.id, {
                  state: "skipped",
                  skipped_at: new Date().toISOString(),
                })
              }
              onDismiss={() =>
                // Dismiss is for failed / rolled_back. State transitions
                // failed|rolled_back → dismissed. The underlying error /
                // rollback evidence stays on the row.
                act(u.id, {
                  state: "dismissed",
                  dismissed_at: new Date().toISOString(),
                })
              }
              onRestore={() =>
                // Restore applies to user-skipped rows. Goes back to
                // available; the CHECK requires other lifecycle columns
                // to be NULL, so clearing skipped_at is enough.
                act(u.id, { state: "available", skipped_at: null })
              }
            />
          );
        };

        return (
          <div className="space-y-3">
            {/* Actionable: in progress, scheduled, failed, rolled back */}
            {actionable.map(renderCard)}

            {/* Latest available release — the one users should upgrade to */}
            {latestWithMigrations && renderCard(latestWithMigrations)}

            {/* Older available releases behind collapsible */}
            {olderAvailable.length > 0 && (
              <Collapsible>
                <CollapsibleTrigger className="flex w-full items-center gap-2 rounded-md border border-dashed border-muted-foreground/25 px-4 py-2 text-sm text-muted-foreground hover:bg-muted/50 transition-colors">
                  <ChevronDown className="h-4 w-4" />
                  {olderAvailable.length} older available upgrade{olderAvailable.length !== 1 ? "s" : ""}
                </CollapsibleTrigger>
                <CollapsibleContent className="space-y-3 mt-3">
                  {olderAvailable.map(renderCard)}
                </CollapsibleContent>
              </Collapsible>
            )}

            {/* Currently-running version — always visible so operators have an
                anchor for "what version am I on right now?". Labeled above the
                card to distinguish it from actionable/available rows. */}
            {latestCompleted && (
              <div className="space-y-2">
                <div className="flex items-center gap-2 px-1 text-sm font-medium text-emerald-800">
                  <CheckCircle2 className="h-4 w-4" />
                  Currently running
                </div>
                {renderCard(latestCompleted)}
              </div>
            )}

            {/* Rest of past upgrades (older completions, superseded, skipped, failed) */}
            {historyRest.length > 0 && (
              <Collapsible>
                <CollapsibleTrigger className="flex w-full items-center gap-2 rounded-md border border-dashed border-muted-foreground/25 px-4 py-2 text-sm text-muted-foreground hover:bg-muted/50 transition-colors">
                  <ChevronDown className="h-4 w-4" />
                  {historyRest.length} past upgrade{historyRest.length !== 1 ? "s" : ""}
                </CollapsibleTrigger>
                <CollapsibleContent className="space-y-3 mt-3">
                  {historyRest.map(renderCard)}
                </CollapsibleContent>
              </Collapsible>
            )}
          </div>
        );
      })()}
    </main>
  );
}

/** Renders changelog text with URLs as clickable links and **bold** as <strong>. */
function ChangelogContent({ text }: { text: string }) {
  // Convert **text** to bold and URLs to links
  const parts = text.split(/(\*\*[^*]+\*\*|https?:\/\/[^\s)]+)/g);
  return (
    <>
      {parts.map((part, i) => {
        if (part.startsWith("**") && part.endsWith("**")) {
          return <strong key={i}>{part.slice(2, -2)}</strong>;
        }
        if (part.startsWith("http://") || part.startsWith("https://")) {
          return (
            <a key={i} href={part} target="_blank" rel="noopener noreferrer">
              {part}
            </a>
          );
        }
        return <span key={i}>{part}</span>;
      })}
    </>
  );
}

function UpgradeCard({
  upgrade: u,
  status,
  acting,
  canRestore,
  onScheduleNow,
  onUnschedule,
  onRefetch,
  onSkip,
  onDismiss,
  onRestore,
}: {
  upgrade: Upgrade;
  status: UpgradeState;
  acting: boolean;
  canRestore: boolean;
  onScheduleNow: () => void;
  onUnschedule: () => void;
  onRefetch: () => void;
  onSkip: () => void;
  onDismiss: () => void;
  onRestore: () => void;
}) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              {u.release_url ? (
                <a href={u.release_url} target="_blank" rel="noopener noreferrer" className="hover:underline">
                  {u.display_name}
                </a>
              ) : (
                u.display_name
              )}
              <Badge variant="outline" className={
                u.release_status === 'release'
                  ? "text-xs border-green-300 text-green-600"
                  : u.release_status === 'prerelease'
                    ? "text-xs border-blue-300 text-blue-600"
                    : "text-xs border-gray-300 text-gray-500"
              }>
                {u.release_status === 'release' ? 'release' : u.release_status === 'prerelease' ? 'pre-release' : 'commit'}
              </Badge>
              {/* Two distinct readiness states, both verified against their
                  respective registries by the upgrade service's discovery
                  cycle. Shown separately so an operator can tell which CI
                  workflow is still running (ci-images.yaml vs release.yaml)
                  and set realistic expectations. */}
              {u.state === 'available' && !u.docker_images_ready && (
                <Badge variant="outline" className="text-xs border-amber-300 text-amber-600">
                  <Loader2 className="mr-1 h-3 w-3 animate-spin" />
                  images building...
                </Badge>
              )}
              {u.state === 'available' && u.release_status !== 'commit' && u.docker_images_ready && !u.release_builds_ready && (
                <Badge variant="outline" className="text-xs border-amber-300 text-amber-600">
                  <Loader2 className="mr-1 h-3 w-3 animate-spin" />
                  release artifacts building...
                </Badge>
              )}
              {u.has_migrations && (
                <Badge variant="outline" className="text-xs border-amber-300 text-amber-600">
                  <Database className="mr-1 h-3 w-3" />
                  migrations
                </Badge>
              )}
            </CardTitle>
            <CardDescription className="mt-1">{u.summary}</CardDescription>
          </div>
          <StateBadge state={status} label={u.display_state} />
        </div>
      </CardHeader>
      <CardContent className="pt-0">
        {/* Meta info */}
        <div className="flex flex-wrap gap-4 text-xs text-muted-foreground mb-3">
          <span>#{u.id}</span>
          <span>
            Committed: {new Date(u.committed_at).toLocaleDateString()}
          </span>
          {u.scheduled_at && (
            <span className="flex items-center gap-1">
              <Calendar className="h-3 w-3" />
              Scheduled: {new Date(u.scheduled_at).toLocaleString()}
            </span>
          )}
          {u.completed_at && (
            <span className="flex items-center gap-1">
              <CheckCircle2 className="h-3 w-3 text-green-600" />
              Completed: {new Date(u.completed_at).toLocaleString()}
            </span>
          )}
        </div>

        {/* Error display */}
        {u.error && (
          <Collapsible defaultOpen>
            <CollapsibleTrigger className="flex items-center gap-1 text-sm font-medium text-red-800 hover:text-red-900">
              <ChevronDown className="h-3 w-3" />
              Error
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-2 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800 whitespace-pre-wrap">
              {u.error}
            </CollapsibleContent>
          </Collapsible>
        )}

        {/* Progress log: the service tail that preceded completion or
            rollback. Opened by default on failures so the operator sees
            what happened without an extra click, closed by default on
            successes (less noise when everything worked). */}
        {u.progress_log && (
          <Collapsible defaultOpen={!!u.error || !!u.rolled_back_at} className="mt-2">
            <CollapsibleTrigger className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
              <ChevronDown className="h-3 w-3" />
              Log
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-2 rounded-md bg-slate-900 p-3 text-xs font-mono text-slate-100 whitespace-pre-wrap">
              {u.progress_log}
            </CollapsibleContent>
          </Collapsible>
        )}

        {/* Changelog */}
        {u.changes && (
          <Collapsible>
            <CollapsibleTrigger className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
              <ChevronDown className="h-3 w-3" />
              Changelog
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-2 rounded-md bg-muted p-3 text-xs whitespace-pre-wrap [&_a]:text-blue-600 [&_a]:underline [&_a]:hover:text-blue-800">
              <ChangelogContent text={u.changes} />
            </CollapsibleContent>
          </Collapsible>
        )}

        {/* Actions */}
        <div className="mt-3 flex gap-2">
          {status === "available" && (
            <>
              {(!u.docker_images_ready || (u.release_status !== 'commit' && !u.release_builds_ready)) ? (
                <span className="text-xs text-amber-600">
                  {!u.docker_images_ready
                    ? "Images building... upgrade will be available when ci-images.yaml finishes."
                    : "Release artifacts building... upgrade will be available when release.yaml finishes."}
                </span>
              ) : (
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button size="sm" disabled={acting}>
                    {acting ? (
                      <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <ArrowDownToLine className="mr-1.5 h-3.5 w-3.5" />
                    )}
                    Upgrade Now
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Confirm Upgrade</AlertDialogTitle>
                    <AlertDialogDescription>
                      This will schedule an immediate upgrade to {u.display_name}.
                      {u.has_migrations &&
                        " This version includes database migrations."}
                      <br />
                      The system will briefly go into maintenance mode during the
                      upgrade.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                    <AlertDialogAction onClick={onScheduleNow}>
                      Proceed
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
              )}
              <Button size="sm" variant="ghost" disabled={acting} onClick={onSkip}>
                <SkipForward className="mr-1.5 h-3.5 w-3.5" />
                Skip
              </Button>
            </>
          )}

          {status === "scheduled" && (
            <Button size="sm" variant="outline" disabled={acting} onClick={onUnschedule}>
              {acting ? (
                <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              ) : (
                <Clock className="mr-1.5 h-3.5 w-3.5" />
              )}
              Unschedule
            </Button>
          )}

          {status === "in_progress" && (
            <Badge className="bg-purple-100 text-purple-800">
              <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              Upgrading...
            </Badge>
          )}

          {(status === "failed" || status === "rolled_back") && (
            <>
              <Button size="sm" variant="outline" disabled={acting} onClick={onDismiss}>
                {acting ? (
                  <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                ) : (
                  <SkipForward className="mr-1.5 h-3.5 w-3.5" />
                )}
                Dismiss
              </Button>
              {u.release_url && (
                <Button size="sm" variant="ghost" asChild>
                  <a
                    href={`https://github.com/statisticsnorway/statbus/issues/new?title=${encodeURIComponent(`Upgrade failed: ${u.display_name}`)}&body=${encodeURIComponent(`## Upgrade Failure Report\n\n**Version:** ${u.display_name}\n**Commit:** ${u.commit_sha}\n**From:** ${u.from_version ?? "unknown"}\n**Error:** ${u.error}\n**Date:** ${u.started_at}`)}`}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <XCircle className="mr-1.5 h-3.5 w-3.5" />
                    Report Issue
                  </a>
                </Button>
              )}
            </>
          )}

          {status === "skipped" && canRestore && (
            <Button size="sm" variant="outline" disabled={acting} onClick={onRestore}>
              {acting ? (
                <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              ) : (
                <RotateCcw className="mr-1.5 h-3.5 w-3.5" />
              )}
              Restore
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
