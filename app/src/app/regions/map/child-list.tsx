"use client";

import { useRef } from "react";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UNIT_TYPE_LABEL, UNIT_TYPE_SWATCH, selectedTotal, type MapUnitType } from "@/components/map/map-data";

/** One child of the selection as the list shows it: a region, or a country at the World level. */
export interface ChildRow {
  /** The selection it stands for: a region path, "" for the installation's country, or "country:SE". */
  path: string;
  name: string;
  /** The region's code beside its name; none for a country. */
  code: string | null;
  counts: Record<MapUnitType, number>;
  /** Whether going in shows anything more (a municipality, the lowest level, has nothing below). */
  canEnter: boolean;
}

/**
 * The children of the Regions map's selection, as a list beside the map (owner 2026-11-24, as on a
 * unit's Map page): each row its name and the units of the picked types, largest first. A click on
 * a row picks it, as a click on its circle does: the row opens with its units per type and View and
 * download, and the circle is ringed. The arrow at the end of a row goes in, as a double click on
 * its circle does. The picked row scrolls into view when it is picked on the map.
 */
export function ChildList({
  heading,
  rows,
  unitTypes,
  picked,
  searchFor,
  onPick,
  onEnter,
}: {
  heading: string;
  rows: ChildRow[];
  unitTypes: readonly MapUnitType[];
  picked: string | null;
  searchFor: (path: string) => string;
  onPick: (path: string | null) => void;
  onEnter: (path: string) => void;
}) {
  const listRef = useRef<HTMLUListElement>(null);
  useGuardedEffect(
    () => {
      if (picked === null) return;
      listRef.current?.querySelector(`[data-child-row="${CSS.escape(picked)}"]`)?.scrollIntoView({ block: "nearest" });
    },
    [picked],
    "ChildList:scrollToPicked"
  );
  const sorted = [...rows].sort((a, b) => selectedTotal(b.counts, unitTypes) - selectedTotal(a.counts, unitTypes) || a.name.localeCompare(b.name));
  return (
    <section data-regions-map-children="">
      <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">{heading}</h2>
      <ul ref={listRef} className="mt-1 space-y-0.5">
        {sorted.map((r) => {
          const isPicked = r.path === picked;
          return (
            <li key={r.path} className={`rounded ${isPicked ? "bg-gray-100" : "hover:bg-gray-100"}`} data-child-row={r.path}>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  className="flex min-w-0 flex-1 items-baseline justify-between gap-2 rounded px-1.5 py-1 text-left"
                  onClick={() => onPick(isPicked ? null : r.path)}
                  aria-expanded={isPicked}
                >
                  <span className="truncate">
                    {r.name}
                    {r.code && <span className="ml-1 text-xs text-gray-500">{r.code}</span>}
                  </span>
                  <span className="tabular-nums text-gray-600">{selectedTotal(r.counts, unitTypes).toLocaleString()}</span>
                </button>
                {r.canEnter ? (
                  <button
                    type="button"
                    className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                    title={`Go into ${r.name}`}
                    aria-label={`Go into ${r.name}`}
                    onClick={() => onEnter(r.path)}
                    data-child-enter={r.path}
                  >
                    <ChevronRight className="h-4 w-4" />
                  </button>
                ) : (
                  <span className="w-6 shrink-0" aria-hidden />
                )}
              </div>
              {isPicked && (
                <div className="space-y-1 px-1.5 pb-2 pt-0.5 text-xs text-gray-600" data-child-detail={r.path}>
                  {unitTypes.map((t) => (
                    <p key={t} className="flex items-center gap-2">
                      <span className={`h-2.5 w-2.5 shrink-0 rounded-full ${UNIT_TYPE_SWATCH[t]}`} aria-hidden />
                      <span className="flex-1">{UNIT_TYPE_LABEL[t]}</span>
                      <span className="tabular-nums">{r.counts[t].toLocaleString()}</span>
                    </p>
                  ))}
                  <Button asChild size="sm" variant="outline" className="mt-1 h-7 w-full">
                    <Link href={searchFor(r.path)}>View and download</Link>
                  </Button>
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
