"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { Search, SquareArrowOutUpRight, X } from "lucide-react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import type { UnitPointProperties } from "./map-data";

const TYPE_LABEL = { legal_unit: "legal unit", establishment: "establishment", enterprise: "enterprise", power_group: "power group" } as const;

/**
 * The units beside a unit's Map page, as the Regions map lists the regions beside its map (owner
 * 2026-11-24): all the enterprise's units from the start, or the group a click on the map picked.
 * A header box says what the list holds and how its units are placed; X goes back to all units.
 * A find field, opened from the search icon, narrows the list by name, Enter picking the first.
 * A click on a row shows the unit on the map and opens the row with where the unit is; the
 * square arrow opens the unit's page. The picked row scrolls into view.
 */
export function UnitsList({
  units,
  heading,
  subheading,
  isAll,
  focused,
  onShow,
  onAll,
}: {
  units: UnitPointProperties[];
  heading: string;
  /** How the listed units are placed, e.g. "3 at their address, 354 somewhere in their region". */
  subheading: string;
  /** Whether the list holds every unit (no X then: there is nothing to go back to). */
  isAll: boolean;
  focused: string | null;
  onShow: (u: UnitPointProperties) => void;
  onAll: () => void;
}) {
  const [query, setQuery] = useState("");
  const [finding, setFinding] = useState(false);
  const listRef = useRef<HTMLUListElement>(null);
  const closeFind = () => {
    setQuery("");
    setFinding(false);
  };
  useGuardedEffect(
    () => {
      if (focused === null) return;
      listRef.current?.querySelector(`[data-picked-unit="${CSS.escape(focused)}"]`)?.scrollIntoView({ block: "nearest" });
    },
    [focused],
    "UnitsList:scrollToFocused"
  );
  const needle = query.trim().toLocaleLowerCase();
  const found = needle ? units.filter((u) => u.name.toLocaleLowerCase().includes(needle) || (u.region_name ?? "").toLocaleLowerCase().includes(needle)) : units;
  const shown = needle ? units.filter((u) => found.includes(u) || `${u.unit_type}:${u.id}` === focused) : units;
  const searchable = units.length > 8;

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {/* What the list holds stays put while the list under it scrolls, as the Regions map's
          selection box does. */}
      <div className="border-b p-3" data-units-map-heading="">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="font-medium">{heading}</p>
            <p className="text-xs text-gray-500">{subheading}</p>
          </div>
          {!isAll && (
            <button
              type="button"
              className="shrink-0 rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900"
              title="Back to all units"
              aria-label="Back to all units"
              onClick={onAll}
              data-units-map-clear=""
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto p-3" data-units-map-picked="">
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
            {units.length === 1 ? "1 unit" : `${units.length.toLocaleString()} units`}
          </p>
          {needle ? (
            <span className="text-xs text-gray-500">{found.length.toLocaleString()} found</span>
          ) : (
            searchable &&
            !finding && (
              <button
                type="button"
                className="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900"
                title="Find a unit by name or region"
                aria-label="Find a unit by name or region"
                onClick={() => setFinding(true)}
                data-units-map-find-open=""
              >
                <Search className="h-3.5 w-3.5" />
              </button>
            )
          )}
        </div>
        {searchable && finding && (
          <div className="relative mt-1">
            <Search className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400" aria-hidden />
            <input
              type="text"
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                // Enter shows the first match, as a click on its row would; Escape folds it away.
                if (e.key === "Enter" && needle && found[0]) onShow(found[0]);
                if (e.key === "Escape") closeFind();
              }}
              placeholder="Find by name or region"
              aria-label="Find a unit by name or region"
              className="w-full rounded border bg-white py-1 pl-7 pr-7 text-sm placeholder:text-gray-400 focus:outline-none focus:ring-1 focus:ring-gray-400"
              data-units-map-find=""
            />
            <button
              type="button"
              className="absolute right-1 top-1/2 -translate-y-1/2 rounded p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-900"
              title="Clear and close"
              aria-label="Clear and close the find field"
              onClick={closeFind}
              data-units-map-find-close=""
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        )}
        <ul ref={listRef} className="mt-1 space-y-0.5">
          {shown.map((u) => {
            const key = `${u.unit_type}:${u.id}`;
            const isFocused = focused === key;
            return (
              <li key={key} className={`rounded ${isFocused ? "bg-gray-100" : "hover:bg-gray-100"}`} data-picked-unit={key}>
                <div className="flex items-start gap-1">
                  {/* A click on the row shows the unit on the map; the arrow opens its page (owner
                      2026-11-24). The row's background covers both, one row with two actions. */}
                  <button
                    type="button"
                    className="flex min-w-0 flex-1 items-start gap-2 rounded px-1 py-0.5 text-left"
                    onClick={() => onShow(u)}
                    aria-expanded={isFocused}
                  >
                    {/* The unit type's marker: a legal unit and its establishment often share a name. */}
                    <span
                      className={`mt-1 inline-block h-2.5 w-2.5 shrink-0 rounded-full ${
                        u.placed === "point"
                          ? u.unit_type === "legal_unit" ? "bg-legal_unit-500" : "bg-establishment-500"
                          : `border-2 bg-white ${u.unit_type === "legal_unit" ? "border-legal_unit-500" : "border-establishment-500"}`
                      }`}
                      title={u.unit_type === "legal_unit" ? "Legal unit" : "Establishment"}
                      aria-hidden
                    />
                    <span className="min-w-0">
                      <span className="break-words">{u.name}</span>
                      <span className="ml-1 text-xs text-gray-500">
                        {TYPE_LABEL[u.unit_type]}
                        {u.current ? ", this unit" : ""}
                      </span>
                    </span>
                  </button>
                  <Link
                    href={u.href}
                    className="mt-0.5 shrink-0 rounded p-1 text-gray-500 hover:bg-gray-200 hover:text-gray-900"
                    title={`Open ${u.name}`}
                    aria-label={`Open ${u.name}`}
                  >
                    <SquareArrowOutUpRight className="h-3.5 w-3.5" />
                  </Link>
                </div>
                {isFocused && (
                  // Where the unit is, as a picked region row says its counts.
                  <p className="px-1 pb-1.5 pl-5 text-xs text-gray-600" data-picked-unit-detail={key}>
                    {u.placed === "point" ? "At its address" : `Somewhere in ${u.region_name ?? "its region"}`}
                    {u.placed === "point" && u.region_name ? `, ${u.region_name}` : ""}
                  </p>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </div>
  );
}
