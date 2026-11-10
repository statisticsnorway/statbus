import type { Enums, Tables } from "@/lib/database.types";

/** A row of public.time_frame: the live frame, a relative frame or a fixed frame. */
export type TimeFrame = Tables<"time_frame">;
export type TimeFrameKind = Enums<"time_frame_kind">;

/** The heading each kind of frame is listed under, in display order. */
export const TIME_FRAME_GROUPS: { kind: TimeFrameKind; heading: string }[] = [
  { kind: "live", heading: "Live frame" },
  { kind: "relative", heading: "Relative frames" },
  { kind: "fixed", heading: "Fixed frames" },
];

export interface TimeFrameGroup {
  kind: TimeFrameKind;
  heading: string;
  frames: TimeFrame[];
}

/**
 * The frames grouped by kind, in public.time_frame's order (live, relative,
 * fixed, newest first). The menu is for looking at data, so `forMenu` leaves
 * out a fixed frame that shows the same year as a relative frame today
 * (equals_frame_ident set: Frame 2025 while Previous frame is 2025). Import
 * pages list every frame, because a job on Previous frame follows the calendar
 * and a job on Frame 2025 does not. Groups without frames are omitted.
 */
export function groupTimeFrames(
  frames: readonly TimeFrame[],
  { forMenu }: { forMenu: boolean }
): TimeFrameGroup[] {
  const shown = forMenu ? frames.filter((f) => !f.equals_frame_ident) : frames;
  return TIME_FRAME_GROUPS.map(({ kind, heading }) => ({
    kind,
    heading,
    frames: shown.filter((f) => f.kind === kind),
  })).filter((group) => group.frames.length > 0);
}
