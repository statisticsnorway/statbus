"use client";

import { useCallback, useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
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

interface Upgrade {
  id: number;
  commit_sha: string;
  committed_at: string;
  position: number | null;
  tags: string[];
  release_status: 'commit' | 'prerelease' | 'release';
  display_name: string;
  summary: string;
  changes: string | null;
  release_url: string | null;
  has_migrations: boolean;
  from_version: string | null;
  scheduled_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  error: string | null;
  rollback_completed_at: string | null;
  skipped_at: string | null;
  images_downloaded: boolean;
  backup_path: string | null;
}

interface SystemInfo {
  key: string;
  value: string;
}

type UpgradeStatus =
  | "available"
  | "scheduled"
  | "in_progress"
  | "completed"
  | "failed"
  | "rolled_back"
  | "skipped";

function getStatus(u: Upgrade): UpgradeStatus {
  if (u.completed_at) return "completed";
  if (u.rollback_completed_at) return "rolled_back";
  if (u.skipped_at) return "skipped";
  if (u.error) return "failed";
  if (u.started_at) return "in_progress";
  if (u.scheduled_at) return "scheduled";
  return "available";
}

function StatusBadge({ status }: { status: UpgradeStatus }) {
  const variants: Record<UpgradeStatus, { label: string; className: string }> =
    {
      available: { label: "Available", className: "bg-blue-100 text-blue-800" },
      scheduled: {
        label: "Scheduled",
        className: "bg-yellow-100 text-yellow-800",
      },
      in_progress: {
        label: "In Progress",
        className: "bg-purple-100 text-purple-800",
      },
      completed: {
        label: "Completed",
        className: "bg-green-100 text-green-800",
      },
      failed: { label: "Failed", className: "bg-red-100 text-red-800" },
      rolled_back: {
        label: "Rolled Back",
        className: "bg-orange-100 text-orange-800",
      },
      skipped: { label: "Skipped", className: "bg-gray-100 text-gray-600" },
    };

  const v = variants[status];
  return <Badge className={v.className}>{v.label}</Badge>;
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
  const {
    data: upgrades,
    error,
    mutate,
  } = useSWR<Upgrade[]>(
    "/rest/upgrade?select=*,display_name&order=position.desc.nullslast,committed_at.desc&limit=20",
    fetcher,
    { refreshInterval: 30000 },
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
  const lastChecked =
    systemInfo?.find((s) => s.key === "upgrade_last_checked")?.value;
  const diskFreeGB = systemInfo?.find((s) => s.key === "disk_free_gb")?.value;
  const diskFree = diskFreeGB ? parseInt(diskFreeGB, 10) : null;

  const [actionError, setActionError] = useState<string | null>(null);

  // Detect when an upgrade takes the app down — show the maintenance page inline.
  const hasActiveUpgrade = upgrades?.some((u) => {
    const s = getStatus(u);
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
        {lastChecked && (
          <span>
            Last checked:{" "}
            <strong className="text-foreground">
              {new Date(lastChecked).toLocaleString()}
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
            No upgrades discovered yet. The upgrade daemon will check
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
          const s = getStatus(u);
          if (s === "completed" || s === "skipped") {
            history.push(u);
          } else if (s === "available") {
            available.push(u);
          } else if (s === "failed" || s === "rolled_back") {
            // Failed/rolled-back go to history — they're done.
            // User can still see error details and report issues.
            history.push(u);
          } else {
            actionable.push(u);
          }
        }

        // When an upgrade is scheduled or in-progress, hide available entries entirely.
        // The user only needs to see the active upgrade, not other options.
        const hasActiveAction = actionable.some((u) => {
          const s = getStatus(u);
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
        const latestCompleted = history.find(u => getStatus(u) === 'completed');

        const renderCard = (u: Upgrade) => {
          const status = getStatus(u);
          const canRestore = latestCompleted
            ? (u.position ?? 0) > (latestCompleted.position ?? 0) || u.committed_at > latestCompleted.committed_at
            : true;
          return (
            <UpgradeCard
              key={u.id}
              upgrade={u}
              status={status}
              acting={acting === u.id}
              canRestore={canRestore}
              onScheduleNow={async () => {
                await act(u.id, { scheduled_at: new Date().toISOString() });
                window.location.href = `/maintenance.html?return=${encodeURIComponent(window.location.pathname)}`;
              }}
              onUnschedule={() => act(u.id, { scheduled_at: null })}
              onRefetch={() =>
                act(u.id, {
                  started_at: null,
                  scheduled_at: null,
                  rollback_completed_at: null,
                })
              }
              onSkip={() =>
                act(u.id, { skipped_at: new Date().toISOString() })
              }
              onRestore={() =>
                act(u.id, { skipped_at: null, error: null })
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

            {/* Completed/skipped history */}
            {history.length > 0 && (
              <Collapsible>
                <CollapsibleTrigger className="flex w-full items-center gap-2 rounded-md border border-dashed border-muted-foreground/25 px-4 py-2 text-sm text-muted-foreground hover:bg-muted/50 transition-colors">
                  <ChevronDown className="h-4 w-4" />
                  {history.length} completed/past upgrade{history.length !== 1 ? "s" : ""}
                </CollapsibleTrigger>
                <CollapsibleContent className="space-y-3 mt-3">
                  {history.map(renderCard)}
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
  onRestore,
}: {
  upgrade: Upgrade;
  status: UpgradeStatus;
  acting: boolean;
  canRestore: boolean;
  onScheduleNow: () => void;
  onUnschedule: () => void;
  onRefetch: () => void;
  onSkip: () => void;
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
              {u.has_migrations && (
                <Badge variant="outline" className="text-xs border-amber-300 text-amber-600">
                  <Database className="mr-1 h-3 w-3" />
                  migrations
                </Badge>
              )}
            </CardTitle>
            <CardDescription className="mt-1">{u.summary}</CardDescription>
          </div>
          <StatusBadge status={status} />
        </div>
      </CardHeader>
      <CardContent className="pt-0">
        {/* Meta info */}
        <div className="flex flex-wrap gap-4 text-xs text-muted-foreground mb-3">
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
              <Button size="sm" variant="outline" disabled={acting} onClick={onRefetch}>
                {acting ? (
                  <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                ) : (
                  <RotateCcw className="mr-1.5 h-3.5 w-3.5" />
                )}
                Retry
              </Button>
              <Button size="sm" variant="ghost" disabled={acting} onClick={onSkip}>
                <SkipForward className="mr-1.5 h-3.5 w-3.5" />
                Skip
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
