"use client";

import { useMemo } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import { restClientAtom } from "@/atoms/rest-client";
import { useTimeFrame } from "@/atoms/app-derived";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { frameMarker } from "./field-timeline";
import type { EditFieldSource } from "./read-edit-range";
import type { SkeletonPiece } from "./timeline-skeleton";
import { unitExistence, type UnitRow } from "./unit-existence";

const formatEnd = (to: string) => (to === "infinity" ? "Present" : to);

/**
 * The unit a record belongs to, from the field's row keys: a contact or location
 * row names its unit by legal_unit_id or establishment_id. A field of the unit
 * itself (its name, status) has none; it is its own existence.
 */
export function parentUnitOf(source: EditFieldSource | undefined): { table: string; id: number } | null {
  if (!source) return null;
  for (const table of ["legal_unit", "establishment"]) {
    const id = source.match[`${table}_id`];
    if (id != null) return { table, id: Number(id) };
  }
  return null;
}

/**
 * Where the record's unit exists (unitExistence), read once per edit: the cap on
 * the record's timeline. Undefined while reading, and for a field of the unit itself.
 */
export function useUnitExistence(source: EditFieldSource | undefined) {
  const client = useAtomValue(restClientAtom);
  const parent = parentUnitOf(source);
  const key = parent && client ? ["unit-existence", parent.table, String(parent.id)] : null;
  const { data } = useSWR(key, async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: rows, error } = await (client as any)
      .from(parent!.table)
      .select("valid_from,valid_until")
      .eq("id", parent!.id)
      .order("valid_from");
    if (error) throw error;
    return rows as UnitRow[];
  });
  return useMemo(() => (data ? unitExistence(data) : undefined), [data]);
}

/**
 * The Timeline view of a record the unit does not have yet: the frames as empty
 * pieces cut to where the unit exists (skeletonPieces), oldest at the top like
 * the field timeline. Ticking pieces picks the stretch the first value fills;
 * a piece the unit does not reach is drawn dashed and cannot be ticked. The
 * unit's first day is marked where it falls, so the cap is visible.
 */
export function TimelineSkeleton({
  pieces,
  picked,
  onToggle,
  unitStart,
}: {
  pieces: readonly SkeletonPiece[];
  picked: readonly number[];
  onToggle: (index: number) => void;
  unitStart: string | undefined;
}) {
  const { selectedTimeFrame } = useTimeFrame();
  const on = (i: number) => picked.includes(i);
  return (
    <div className="space-y-1" data-timeline-skeleton="">
      <div className="grid grid-cols-[minmax(3.5rem,auto)_1rem_1rem_1fr] gap-x-2 text-sm">
        {pieces.map((p, i) => {
          const marker = p.frame ? frameMarker(p.frame) : null;
          const looking = p.frame && (p.frame.ident === selectedTimeFrame?.ident || p.frame.ident === selectedTimeFrame?.equals_frame_ident);
          const startsHere = !!unitStart && p.available && p.valid_from === unitStart;
          const linkUp = on(i) && on(i - 1);
          const linkDown = on(i) && on(i + 1);
          return (
            <div key={`${p.frame?.ident ?? "earlier"}-${p.valid_from}`} className="contents" data-skeleton-piece={p.frame?.ident ?? "earlier"} data-available={p.available || undefined} data-picked={on(i) || undefined}>
              <div
                className={cn(
                  "my-0.5 flex flex-col justify-center border-l-2 pl-1.5 text-xs leading-4",
                  looking ? "border-zinc-700 font-medium text-zinc-900" : "border-zinc-200 text-zinc-500",
                  !p.available && "opacity-50"
                )}
              >
                {marker ? (
                  <>
                    <span>{marker.label}</span>
                    {marker.year && <span className="tabular-nums">{marker.year}</span>}
                  </>
                ) : (
                  "Earlier"
                )}
              </div>
              <div className="relative flex min-h-10 items-start justify-center" aria-hidden>
                <span className={cn("absolute left-1/2 top-0 h-3 -translate-x-1/2", i === 0 ? "hidden" : linkUp ? "w-1 bg-ssb-dark" : "w-px bg-zinc-300", !p.available && "bg-transparent border-l border-dashed border-zinc-300")} />
                <span className={cn("absolute bottom-0 left-1/2 top-3 -translate-x-1/2", i === pieces.length - 1 ? "hidden" : linkDown ? "w-1 bg-ssb-dark" : "w-px bg-zinc-300", !p.available && "bg-transparent border-l border-dashed border-zinc-300")} />
                <span className={cn("relative z-10 mt-1.5 h-3 w-3 rounded-full border-2", on(i) ? "border-ssb-dark bg-white" : p.available ? "border-zinc-400 bg-white" : "border-dashed border-zinc-300 bg-white")} />
              </div>
              <div className="pt-1.5">
                <Checkbox
                  checked={on(i)}
                  disabled={!p.available}
                  onCheckedChange={() => onToggle(i)}
                  aria-label={`Fill ${p.valid_from} – ${formatEnd(p.valid_to)}`}
                />
              </div>
              <div
                className={cn(
                  "my-0.5 min-w-0 rounded border px-2 py-1",
                  on(i) ? "border-ssb-dark/30 bg-ssb-light" : p.available ? "border-dashed border-zinc-300" : "border-dashed border-zinc-200 text-zinc-400"
                )}
              >
                <div className={cn("italic", p.available ? "text-zinc-500" : "text-zinc-400")}>
                  {p.available ? (on(i) ? "New value" : "Empty") : "Unit does not exist"}
                </div>
                <div className="text-xs text-zinc-500">
                  {p.valid_from} – {formatEnd(p.valid_to)}
                  {startsHere && <span className="font-medium text-zinc-700"> · unit starts {unitStart}</span>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
