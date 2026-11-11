"use client";
import { InfoPopover } from "@/components/info-popover";
import type { TimeFrameGroup } from "@/lib/time-frame";

/**
 * A frame group's heading with the (i) that explains the kind of frame
 * (TIME_FRAME_GROUPS in lib/time-frame.ts). Used by the frame menu, the
 * import pages, the edit form and the command palette.
 */
export function TimeFrameGroupHeading({ group }: { readonly group: Pick<TimeFrameGroup, "kind" | "heading" | "explanation"> }) {
  return (
    <span className="inline-flex items-center gap-1">
      {group.heading}
      <InfoPopover label={`About ${group.heading.toLowerCase()}`} title={group.heading} data-time-frame-info={group.kind}>
        {group.explanation}
      </InfoPopover>
    </span>
  );
}
