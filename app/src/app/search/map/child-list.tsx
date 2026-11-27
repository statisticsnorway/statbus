"use client";

import { useRef, useState } from "react";
import { Eye, Search, X } from "lucide-react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import {
  UNIT_TYPE_LABEL,
  UNIT_TYPE_SWATCH,
  selectedTotal,
  type MapUnitType,
} from "@/components/map/map-data";

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
 * The children of the search map's selection, as a list beside the map (owner 2026-11-24, as on a
 * unit's Map page): each row its name and the units of the picked types, largest first. A click on
 * a row goes into it, as the list's natural step (owner 2026-11-27; a region at the lowest level is
 * then shown alone). The eye shows where it is without going in: its circle is ringed and brought
 * into view, and the row opens with its units per type, as a click on the circle does. On the map
 * a click picks and a double click goes in. The picked row scrolls into view when it is picked on
 * the map.
 */
export function ChildList({
  heading,
  rows,
  unitTypes,
  picked,
  onPick,
  onEnter,
}: {
  heading: string;
  rows: ChildRow[];
  unitTypes: readonly MapUnitType[];
  picked: string | null;
  onPick: (path: string | null) => void;
  onEnter: (path: string) => void;
}) {
  const listRef = useRef<HTMLUListElement>(null);
  // Narrows the list to the regions whose name or code contains the text (owner 2026-11-24: the
  // list is by size, so one region among many is hard to find). Shown when the list is long.
  const [query, setQuery] = useState("");
  // The field opens from a search icon by the heading and folds away again with its X (owner
  // 2026-11-24), so a short list or a list not being searched shows no empty field.
  const [finding, setFinding] = useState(false);
  const searchable = rows.length > 8;
  const closeFind = () => {
    setQuery("");
    setFinding(false);
  };
  useGuardedEffect(
    () => {
      if (picked === null) return;
      listRef.current
        ?.querySelector(`[data-child-row="${CSS.escape(picked)}"]`)
        ?.scrollIntoView({ block: "nearest" });
    },
    [picked],
    "ChildList:scrollToPicked"
  );
  const sorted = [...rows].sort(
    (a, b) =>
      selectedTotal(b.counts, unitTypes) - selectedTotal(a.counts, unitTypes) ||
      a.name.localeCompare(b.name)
  );
  const needle = query.trim().toLocaleLowerCase();
  const matches = (r: ChildRow) =>
    r.name.toLocaleLowerCase().includes(needle) ||
    (r.code ?? "").includes(needle);
  const found = needle ? sorted.filter(matches) : sorted;
  // The picked region stays in the list while finding another, so it can still be unpicked.
  const shown = needle
    ? sorted.filter((r) => matches(r) || r.path === picked)
    : sorted;
  return (
    <section data-regions-map-children="">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-xs font-medium uppercase tracking-wide text-gray-500">
          {heading}
        </h2>
        {needle ? (
          <span className="text-xs text-gray-500">
            {found.length.toLocaleString()} found
          </span>
        ) : (
          searchable &&
          !finding && (
            <button
              type="button"
              className="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900"
              title="Find a region by name or code"
              aria-label="Find a region by name or code"
              onClick={() => setFinding(true)}
              data-regions-map-find-open=""
            >
              <Search className="h-3.5 w-3.5" />
            </button>
          )
        )}
      </div>
      {searchable && finding && (
        <div className="relative mt-1">
          <Search
            className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400"
            aria-hidden
          />
          <input
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              // Enter goes into the first match, as a click on its row would; Escape folds it away.
              if (e.key === "Enter" && needle && found[0])
                onEnter(found[0].path);
              if (e.key === "Escape") closeFind();
            }}
            placeholder="Find by name or code"
            aria-label="Find a region by name or code"
            className="w-full rounded border bg-white py-1 pl-7 pr-7 text-sm placeholder:text-gray-400 focus:outline-none focus:ring-1 focus:ring-gray-400"
            data-regions-map-find=""
          />
          <button
            type="button"
            className="absolute right-1 top-1/2 -translate-y-1/2 rounded p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-900"
            title="Clear and close"
            aria-label="Clear and close the find field"
            onClick={closeFind}
            data-regions-map-find-close=""
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}
      <ul ref={listRef} className="mt-1 space-y-0.5">
        {shown.map((r) => {
          const isPicked = r.path === picked;
          return (
            <li
              key={r.path}
              className={`rounded ${isPicked ? "bg-gray-100" : "hover:bg-gray-100"}`}
              data-child-row={r.path}
            >
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  className="flex min-w-0 flex-1 items-baseline justify-between gap-2 rounded px-1.5 py-1 text-left"
                  onClick={() => onEnter(r.path)}
                  title={
                    r.canEnter ? `Go into ${r.name}` : `Show only ${r.name}`
                  }
                  data-child-enter={r.path}
                >
                  <span className="truncate">
                    {r.name}
                    {r.code && (
                      <span className="ml-1 text-xs text-gray-500">
                        {r.code}
                      </span>
                    )}
                  </span>
                  <span className="tabular-nums text-gray-600">
                    {selectedTotal(r.counts, unitTypes).toLocaleString()}
                  </span>
                </button>
                <button
                  type="button"
                  className={`shrink-0 rounded p-1 hover:bg-gray-200 hover:text-gray-900 ${isPicked ? "text-gray-900" : "text-gray-400"}`}
                  title={
                    isPicked
                      ? `Hide where ${r.name} is`
                      : `Show where ${r.name} is`
                  }
                  aria-label={
                    isPicked
                      ? `Hide where ${r.name} is`
                      : `Show where ${r.name} is`
                  }
                  aria-pressed={isPicked}
                  onClick={() => onPick(isPicked ? null : r.path)}
                  data-child-show={r.path}
                >
                  <Eye className="h-4 w-4" />
                </button>
              </div>
              {isPicked && (
                <div
                  className="space-y-1 px-1.5 pb-2 pt-0.5 text-xs text-gray-600"
                  data-child-detail={r.path}
                >
                  {unitTypes.map((t) => (
                    <p key={t} className="flex items-center gap-2">
                      <span
                        className={`h-2.5 w-2.5 shrink-0 rounded-full ${UNIT_TYPE_SWATCH[t]}`}
                        aria-hidden
                      />
                      <span className="flex-1">{UNIT_TYPE_LABEL[t]}</span>
                      <span className="tabular-nums">
                        {r.counts[t].toLocaleString()}
                      </span>
                    </p>
                  ))}
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
