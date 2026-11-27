"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { useWorkerStatus } from "@/atoms/worker_status";

/**
 * The map panels' placeholder while their figures are read, in the search list's look (owner
 * 2026-11-27 22:24: on a slow machine a zero could not be told from figures still on their way).
 * `rows` lines of a name and a number, pulsing.
 */
export function MapPanelSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div className="space-y-2" role="status" aria-label="Reading the figures" data-map-panel-skeleton="">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="flex items-center justify-between gap-3">
          <Skeleton className="h-4" style={{ width: `${45 + ((i * 17) % 35)}%` }} />
          <Skeleton className="h-4 w-14" />
        </div>
      ))}
    </div>
  );
}

/**
 * Why the map shows no units in the frame, said in words rather than as zeros: the frame has none
 * (a register whose data starts later), or the figures are being recalculated (the derive the
 * worker runs after an import or an upgrade), in which case they may be incomplete.
 */
export function MapEmptyNote({ frameName }: { frameName: string | null }) {
  return (
    <p className="rounded border border-dashed border-gray-300 p-2 text-xs text-gray-600" data-map-empty="">
      No units in {frameName ?? "this frame"}. Another frame, chosen at the top right, may have some.
    </p>
  );
}

/** A quiet line while the worker recalculates the figures the map reads (statistical units or reports). */
export function MapRecalculatingNote() {
  const { isDerivingUnits, isDerivingReports } = useWorkerStatus();
  if (!isDerivingUnits && !isDerivingReports) return null;
  return (
    <p className="flex items-center gap-1.5 text-xs text-amber-700" role="status" data-map-recalculating="">
      <span className="inline-block h-2 w-2 animate-pulse rounded-full bg-amber-500" aria-hidden />
      The figures are being recalculated; until that is done they may be incomplete.
    </p>
  );
}
