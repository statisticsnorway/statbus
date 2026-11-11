"use client";
import { Info } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

/**
 * A small (i) that opens a short explanation on click. The one way the app
 * offers details behind a brief label: frame group headings, the job list's
 * Source column. Click, not hover, so it works on touch screens and inside
 * menus and lists, which keep their own keyboard handling.
 */
export function InfoPopover({
  label,
  title,
  children,
  side = "left",
  className,
  ...data
}: {
  /** What the icon explains, read by screen readers: "About relative frames". */
  readonly label: string;
  readonly title?: React.ReactNode;
  readonly children: React.ReactNode;
  readonly side?: "left" | "right" | "top" | "bottom";
  readonly className?: string;
} & { [key: `data-${string}`]: string | undefined }) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={label}
          className={cn(
            "rounded-full p-0.5 text-zinc-400 hover:text-zinc-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400",
            className
          )}
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
          {...data}
        >
          <Info className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side={side} align="start" className="w-72 text-sm font-normal normal-case text-zinc-700">
        {title && <p className="font-medium text-zinc-900">{title}</p>}
        <div className={cn(title && "mt-1")}>{children}</div>
      </PopoverContent>
    </Popover>
  );
}
