"use client"

import * as React from "react"
import { cn } from "@/lib/utils"

interface StackedProgressSegment {
  value: number;
  className: string;
}

interface StackedProgressProps {
  segments: StackedProgressSegment[];
  className?: string;
}

function StackedProgress({ segments, className }: StackedProgressProps) {
  return (
    <div
      data-slot="stacked-progress"
      className={cn(
        "bg-zinc-900/20 relative h-2 w-full overflow-hidden rounded-full dark:bg-zinc-50/20",
        className
      )}
    >
      {segments.map((segment, i) => (
        <div
          key={i}
          className={cn("h-full absolute top-0 transition-all", segment.className)}
          style={{
            left: `${segments.slice(0, i).reduce((sum, s) => sum + s.value, 0)}%`,
            width: `${segment.value}%`,
          }}
        />
      ))}
    </div>
  )
}

export { StackedProgress, type StackedProgressProps, type StackedProgressSegment }
