import type { TimeFrame } from "@/lib/time-frame";
import { capToExistence, type ExistenceSpan } from "./unit-existence";

/**
 * The Timeline view of a record a unit does not have yet, such as a first contact
 * or a first postal address: a skeleton of empty pieces, one per time frame, to
 * pick the stretch the new value fills (owner 2026-11-12, STATBUS-609).
 *
 * The record can exist only where its unit exists (unitExistence), so the unit's
 * existence caps the skeleton. Each frame's piece is cut to that existence; a
 * frame the unit does not reach is drawn but cannot be picked. Time before the
 * oldest frame, when the unit existed then, is one more piece. The Live frame's
 * piece is picked to start with, so a first value starts in Live, or where the
 * unit starts when it was born inside Live.
 *
 * Dates are ISO yyyy-mm-dd, valid_to inclusive, "infinity" for open-ended.
 */
export interface SkeletonPiece {
  /** The frame the piece is cut from; null for the time before the oldest frame. */
  frame: TimeFrame | null;
  valid_from: string;
  valid_to: string;
  /** False when the unit does not exist anywhere in the frame: drawn, not pickable. */
  available: boolean;
}

function dayBefore(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

export function skeletonPieces(
  frames: readonly TimeFrame[],
  existence: readonly ExistenceSpan[]
): SkeletonPiece[] {
  const ordered = frames
    .filter((f) => !f.equals_frame_ident && f.valid_from != null && f.valid_to != null)
    .sort((a, b) => (a.valid_from! < b.valid_from! ? -1 : 1));
  const pieces: SkeletonPiece[] = [];
  const unitStart = existence[0]?.validFrom;
  const oldest = ordered[0]?.valid_from;
  if (unitStart && oldest && unitStart < oldest) {
    const before = capToExistence(existence, unitStart, dayBefore(oldest));
    if (before) pieces.push({ frame: null, valid_from: before.validFrom, valid_to: before.validTo, available: true });
  }
  for (const frame of ordered) {
    const capped = capToExistence(existence, frame.valid_from!, frame.valid_to!);
    pieces.push(
      capped
        ? { frame, valid_from: capped.validFrom, valid_to: capped.validTo, available: true }
        : { frame, valid_from: frame.valid_from!, valid_to: frame.valid_to!, available: false }
    );
  }
  return pieces;
}

/** The picked pieces as the edit's dates: from the first picked piece's start to the last one's end. */
export function skeletonSelectionRange(
  pieces: readonly SkeletonPiece[],
  picked: readonly number[]
): { validFrom: string; validTo: string } | null {
  if (picked.length === 0) return null;
  return {
    validFrom: pieces[Math.min(...picked)].valid_from,
    validTo: pieces[Math.max(...picked)].valid_to,
  };
}
