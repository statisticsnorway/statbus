"use client";

import { Skeleton } from "@/components/ui/skeleton";

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
 * Why the map shows no units in the frame, said in words rather than as zeros (a register whose
 * data starts later than the frame). A recalculation in progress is shown once for the whole app,
 * by the progress mark beside Statistical Units and Reports in the top bar (owner 2026-11-27 22:35),
 * so the map does not repeat it.
 */
export function MapEmptyNote({ frameName }: { frameName: string | null }) {
  return (
    <p className="rounded border border-dashed border-gray-300 p-2 text-xs text-gray-600" data-map-empty="">
      No units in {frameName ?? "this frame"}. Another frame, chosen at the top right, may have some.
    </p>
  );
}
