"use client";
import { Info } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import type { TimeFrameGroup } from "@/lib/time-frame";

/**
 * A frame group's heading with an info icon that explains the kind of frame
 * (TIME_FRAME_GROUPS in lib/time-frame.ts). Used by the frame menu, the import
 * pages and the command palette, so every list explains frames the same way.
 * The icon opens on click, which works inside menus and select lists where a
 * hover tooltip would compete with keyboard navigation.
 */
export function TimeFrameGroupHeading({ group }: { readonly group: Pick<TimeFrameGroup, "kind" | "heading" | "explanation"> }) {
  return (
    <span className="inline-flex items-center gap-1">
      {group.heading}
      <Popover>
        <PopoverTrigger asChild>
          <button
            type="button"
            aria-label={`About ${group.heading.toLowerCase()}`}
            data-time-frame-info={group.kind}
            className="rounded-full p-0.5 text-zinc-400 hover:text-zinc-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => e.stopPropagation()}
          >
            <Info className="h-3.5 w-3.5" />
          </button>
        </PopoverTrigger>
        <PopoverContent side="left" align="start" className="w-72 text-sm font-normal normal-case text-zinc-700">
          <p className="font-medium text-zinc-900">{group.heading}</p>
          <p className="mt-1">{group.explanation}</p>
        </PopoverContent>
      </Popover>
    </span>
  );
}
