"use client";

import { X } from "lucide-react";
import type { DrillDownPoint } from "@/app/reports/types/drill-down";

/**
 * The other panel's choice, said in this panel: the Drilldown's region and activity limit each
 * other, so the region bars and map count only the chosen activity and the activity bars only
 * the chosen region (owner 2026-11-28 14:24: it has to be obvious that the limit applies to the
 * map as well). The X lifts it here, without scrolling to the other panel.
 */
export function WithinNote({
  kind,
  point,
  onClear,
}: {
  readonly kind: "region" | "activity";
  readonly point: DrillDownPoint | null;
  readonly onClear: () => void;
}) {
  if (!point) return null;
  const what = kind === "region" ? "region" : "activity";
  return (
    <p className="mt-1 flex items-center gap-1.5 px-3 text-sm text-gray-700" data-drilldown-within={kind}>
      <span className="text-gray-500">Only units in {what}</span>
      <span className="rounded border border-gray-300 bg-white px-1.5 py-0.5 font-medium">
        {point.path} - {point.name}
      </span>
      <button
        type="button"
        className="rounded p-0.5 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
        title={`Show every ${what}`}
        aria-label={`Show every ${what}`}
        onClick={onClear}
      >
        <X className="h-3.5 w-3.5" />
      </button>
    </p>
  );
}
