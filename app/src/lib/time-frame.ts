import type { Enums, Tables } from "@/lib/database.types";

/** A row of public.time_frame: the live frame, a relative frame or a fixed frame. */
export type TimeFrame = Tables<"time_frame">;
export type TimeFrameKind = Enums<"time_frame_kind">;

/**
 * The heading each kind of frame is listed under, in display order, and the
 * explanation shown by the info icon beside it.
 */
export const TIME_FRAME_GROUPS: { kind: TimeFrameKind; heading: string; explanation: string }[] = [
  {
    kind: "live",
    heading: "Live frame",
    explanation:
      "The current year onwards, as the register looks today. New imports and edits land here, and it keeps changing as they do.",
  },
  {
    kind: "relative",
    heading: "Relative frames",
    explanation:
      "A closed year named by its place in the calendar: Previous frame is always last year. It moves on 1 January, so a recurring import job on Previous frame loads last year every year.",
  },
  {
    kind: "fixed",
    heading: "Fixed frames",
    explanation:
      "One closed year named by its number, the same year forever. Use it to look back at, or load into, that particular year. A fixed frame equal to a relative frame is listed only under the relative frame in the menu.",
  },
];

export interface TimeFrameGroup {
  kind: TimeFrameKind;
  heading: string;
  explanation: string;
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
  return TIME_FRAME_GROUPS.map(({ kind, heading, explanation }) => ({
    kind,
    heading,
    explanation,
    frames: shown.filter((f) => f.kind === kind),
  })).filter((group) => group.frames.length > 0);
}
