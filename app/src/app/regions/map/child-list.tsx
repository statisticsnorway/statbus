"use client";

import { useRef, useState } from "react";
import { ChevronRight, Search } from "lucide-react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { UNIT_TYPE_LABEL, UNIT_TYPE_SWATCH, selectedTotal, type MapUnitType } from "@/components/map/map-data";
import { OpenInSearch, unitsIn } from "./open-in-search";

/** One child of the selection as the list shows it: a region, or a country at the World level. */
export interface ChildRow {
  /** The selection it stands for: a region path, "" for the installation's country, or "country:SE". */
  path: string;
  name: string;
  /** The region's code beside its name; none for a country. */
  code: string | null;
  counts: Record<MapUnitType, number>;
  /** Whether going in shows anything more; a region at the lowest level is then shown alone. */
  canEnter: boolean;
}

/**
 * The children of the Regions map's selection, as a list beside the map (owner 2026-11-24, as on a
 * unit's Map page): each row its name and the units of the picked types, largest first. A click on
 * a row picks it, as a click on its circle does: the row opens with its units per type, the square
 * arrow opens them in the search, and the circle is ringed. The picked row's button, or the
 * chevron at a row's end, goes in (a region at the lowest level is then shown alone); on the map a
 * double click on its circle does the same. The picked row scrolls into view when it is picked on
 * the map.
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
  // Narrows the list to the regions whose name or code contains the text (owner 2026-11-24: the
  // list is by size, so one region among many is hard to find). Shown when the list is long.
  const [query, setQuery] = useState("");
  const searchable = rows.length > 8;
  useGuardedEffect(
    () => {
      if (picked === null) return;
      listRef.current?.querySelector(`[data-child-row="${CSS.escape(picked)}"]`)?.scrollIntoView({ block: "nearest" });
    },
    [picked],
    "ChildList:scrollToPicked"
  );
  const sorted = [...rows].sort((a, b) => selectedTotal(b.counts, unitTypes) - selectedTotal(a.counts, unitTypes) || a.name.localeCompare(b.name));
  const needle = query.trim().toLocaleLowerCase();
  const matches = (r: ChildRow) => r.name.toLocaleLowerCase().includes(needle) || (r.code ?? "").includes(needle);
  const found = needle ? sorted.filter(matches) : sorted;
  // The picked region stays in the list while finding another, so it can still be unpicked.
  const shown = needle ? sorted.filter((r) => matches(r) || r.path === picked) : sorted;
  return (
    <section data-regions-map-children="">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">{heading}</h2>
        {needle && <span className="text-xs text-gray-500">{found.length.toLocaleString()} found</span>}
      </div>
      {searchable && (
        <div className="relative mt-1">
          <Search className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400" aria-hidden />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              // Enter picks the first match, as a click on its row would.
              if (e.key === "Enter" && needle && found[0]) onPick(found[0].path);
              if (e.key === "Escape") setQuery("");
            }}
            placeholder="Find by name or code"
            aria-label="Find a region by name or code"
            className="w-full rounded border bg-white py-1 pl-7 pr-2 text-sm placeholder:text-gray-400 focus:outline-none focus:ring-1 focus:ring-gray-400"
            data-regions-map-find=""
          />
        </div>
      )}
      <ul ref={listRef} className="mt-1 space-y-0.5">
        {shown.map((r) => {
          const isPicked = r.path === picked;
          return (
            <li key={r.path} className={`rounded ${isPicked ? "bg-gray-100" : "hover:bg-gray-100"}`} data-child-row={r.path}>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  className="flex min-w-0 flex-1 items-baseline justify-between gap-2 rounded px-1.5 py-1 text-left"
                  // A click picks the row (or unpicks it). Going in is the chevron, or the button
                  // in the picked row, not a double click: a list does not suggest one (owner
                  // 2026-11-24); on the map a double click on the circle still goes in.
                  onClick={() => onPick(isPicked ? null : r.path)}
                  aria-expanded={isPicked}
                >
                  <span className="truncate">
                    {r.name}
                    {r.code && <span className="ml-1 text-xs text-gray-500">{r.code}</span>}
                  </span>
                  <span className="tabular-nums text-gray-600">{selectedTotal(r.counts, unitTypes).toLocaleString()}</span>
                </button>
                {isPicked && <OpenInSearch href={searchFor(r.path)} title={unitsIn(r.name)} data-child-search={r.path} />}
                <button
                  type="button"
                  className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                  title={r.canEnter ? `Go into ${r.name}` : `Show only ${r.name}`}
                  aria-label={r.canEnter ? `Go into ${r.name}` : `Show only ${r.name}`}
                  onClick={() => onEnter(r.path)}
                  data-child-enter={r.path}
                >
                  <ChevronRight className="h-4 w-4" />
                </button>
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
                  {/* Going in, said in words where the row is picked, so it is found without
                      knowing the chevron or the map's double click (owner 2026-11-24). */}
                  <button
                    type="button"
                    className="mt-1 flex w-full items-center justify-center gap-1 rounded border bg-white px-2 py-1 text-xs font-medium text-gray-800 hover:bg-gray-50"
                    onClick={() => onEnter(r.path)}
                    data-child-enter-button={r.path}
                  >
                    {r.canEnter ? `Go into ${r.name}` : `Show only ${r.name}`}
                    <ChevronRight className="h-3.5 w-3.5" />
                  </button>
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
