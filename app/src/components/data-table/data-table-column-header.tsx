"use client";

import type { Column } from "@tanstack/react-table";
import {
  ChevronDown,
  ChevronUp,
  ChevronsUpDown,
  EyeOff,
  X,
} from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

interface DataTableColumnHeaderProps<TData, TValue>
  extends React.ComponentProps<typeof DropdownMenuTrigger> {
  column: Column<TData, TValue>;
  title: string;
  /**
   * "center" for short values such as IDs: the title sits centred over the
   * values, with the sort arrow just right of it. Give such a column a narrow
   * size, so the space on both sides of its values stays even.
   * Default: left, in line with the cells.
   */
  align?: "left" | "center";
}

export function DataTableColumnHeader<TData, TValue>({
  column,
  title,
  align = "left",
  className,
  ...props
}: DataTableColumnHeaderProps<TData, TValue>) {
  const centred = align === "center";
  if (!column.getCanSort() && !column.getCanHide()) {
    return <div className={cn(centred && "text-center", className)}>{title}</div>;
  }

  return (
    <DropdownMenu>
      {/* The title lines up with the column's cells (left, or centred over
          them); the sort arrow hangs just right of the title, outside that
          alignment, so it neither widens the column nor moves the title away
          from the values below it. */}
      <DropdownMenuTrigger
        className={cn(
          "relative flex h-8 items-center rounded-md px-1 py-1.5 hover:bg-zinc-100 focus:outline-none focus:ring-1 focus:ring-zinc-950 data-[state=open]:bg-zinc-100 [&_svg]:size-4 [&_svg]:shrink-0 [&_svg]:text-zinc-500 dark:hover:bg-zinc-800 dark:focus:ring-zinc-300 dark:data-[state=open]:bg-zinc-800 dark:[&_svg]:text-zinc-400",
          centred ? "mx-auto" : "-mx-1 pr-6",
          className,
        )}
        {...props}
      >
        {title}
        {column.getCanSort() && (
          <span
            className={cn("absolute top-1/2 -translate-y-1/2", centred ? "left-full" : "right-1")}
            data-sort-indicator
          >
            {column.getIsSorted() === "desc" ? (
              <ChevronDown />
            ) : column.getIsSorted() === "asc" ? (
              <ChevronUp />
            ) : (
              <ChevronsUpDown />
            )}
          </span>
        )}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-28">
        {column.getCanSort() && (
          <>
            <DropdownMenuCheckboxItem
              className="relative pr-8 pl-2 [&>span:first-child]:right-2 [&>span:first-child]:left-auto [&_svg]:text-zinc-500 dark:[&_svg]:text-zinc-400"
              checked={column.getIsSorted() === "asc"}
              onClick={() => column.toggleSorting(false)}
            >
              <ChevronUp />
              Asc
            </DropdownMenuCheckboxItem>
            <DropdownMenuCheckboxItem
              className="relative pr-8 pl-2 [&>span:first-child]:right-2 [&>span:first-child]:left-auto [&_svg]:text-zinc-500 dark:[&_svg]:text-zinc-400"
              checked={column.getIsSorted() === "desc"}
              onClick={() => column.toggleSorting(true)}
            >
              <ChevronDown />
              Desc
            </DropdownMenuCheckboxItem>
            {column.getIsSorted() && (
              <DropdownMenuItem
                className="pl-2 [&_svg]:text-zinc-500 dark:[&_svg]:text-zinc-400"
                onClick={() => column.clearSorting()}
              >
                <X />
                Reset
              </DropdownMenuItem>
            )}
          </>
        )}
        {column.getCanHide() && (
          <DropdownMenuCheckboxItem
            className="relative pr-8 pl-2 [&>span:first-child]:right-2 [&>span:first-child]:left-auto [&_svg]:text-zinc-500 dark:[&_svg]:text-zinc-400"
            checked={!column.getIsVisible()}
            onClick={() => column.toggleVisibility(false)}
          >
            <EyeOff />
            Hide
          </DropdownMenuCheckboxItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
