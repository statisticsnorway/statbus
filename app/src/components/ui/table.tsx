"use client"

import * as React from "react"

import { cn } from "@/lib/utils"

// Marks the scroll box with data-overflows-left/right while columns are hidden under that edge,
// so pinned columns (data-pinned-edge) show their dashed edge only when something runs beneath them.
function trackHorizontalOverflow(box: HTMLDivElement | null) {
  if (!box) return
  const update = () => {
    box.toggleAttribute("data-overflows-left", box.scrollLeft > 1)
    box.toggleAttribute(
      "data-overflows-right",
      box.scrollWidth - box.clientWidth - box.scrollLeft > 1
    )
  }
  update()
  box.addEventListener("scroll", update, { passive: true })
  const resize = new ResizeObserver(update)
  resize.observe(box)
  if (box.firstElementChild) resize.observe(box.firstElementChild)
  return () => {
    box.removeEventListener("scroll", update)
    resize.disconnect()
  }
}

function Table({ className, ...props }: React.ComponentProps<"table">) {
  return (
    <div
      ref={trackHorizontalOverflow}
      data-slot="table-container"
      className="relative w-full overflow-x-auto [&[data-overflows-right]_[data-pinned-edge=right]]:border-l [&[data-overflows-right]_[data-pinned-edge=right]]:border-dashed [&[data-overflows-left]_[data-pinned-edge=left]]:border-r [&[data-overflows-left]_[data-pinned-edge=left]]:border-dashed"
    >
      <table
        data-slot="table"
        className={cn("w-full caption-bottom text-sm", className)}
        {...props}
      />
    </div>
  )
}

function TableHeader({ className, ...props }: React.ComponentProps<"thead">) {
  return (
    <thead
      data-slot="table-header"
      className={cn("[&_tr]:border-b", className)}
      {...props}
    />
  )
}

function TableBody({ className, ...props }: React.ComponentProps<"tbody">) {
  return (
    <tbody
      data-slot="table-body"
      className={cn("[&_tr:last-child]:border-0", className)}
      {...props}
    />
  )
}

function TableFooter({ className, ...props }: React.ComponentProps<"tfoot">) {
  return (
    <tfoot
      data-slot="table-footer"
      className={cn(
        "bg-zinc-100/50 border-t font-medium [&>tr]:last:border-b-0 dark:bg-zinc-800/50",
        className
      )}
      {...props}
    />
  )
}

function TableRow({ className, ...props }: React.ComponentProps<"tr">) {
  return (
    <tr
      data-slot="table-row"
      className={cn(
        "hover:bg-zinc-100/50 data-[state=selected]:bg-zinc-100 border-b transition-colors dark:hover:bg-zinc-800/50 dark:data-[state=selected]:bg-zinc-800",
        className
      )}
      {...props}
    />
  )
}

function TableHead({ className, ...props }: React.ComponentProps<"th">) {
  return (
    <th
      data-slot="table-head"
      className={cn(
        "text-zinc-950 h-10 px-2 text-left align-middle font-medium whitespace-nowrap [&:has([role=checkbox])]:pr-0 [&>[role=checkbox]]:translate-y-[2px] dark:text-zinc-50",
        className
      )}
      {...props}
    />
  )
}

function TableCell({ className, ...props }: React.ComponentProps<"td">) {
  return (
    <td
      data-slot="table-cell"
      className={cn(
        "p-2 align-middle whitespace-nowrap [&:has([role=checkbox])]:pr-0 [&>[role=checkbox]]:translate-y-[2px]",
        className
      )}
      {...props}
    />
  )
}

function TableCaption({
  className,
  ...props
}: React.ComponentProps<"caption">) {
  return (
    <caption
      data-slot="table-caption"
      className={cn("text-zinc-500 mt-4 text-sm dark:text-zinc-400", className)}
      {...props}
    />
  )
}

export {
  Table,
  TableHeader,
  TableBody,
  TableFooter,
  TableHead,
  TableRow,
  TableCell,
  TableCaption,
}
