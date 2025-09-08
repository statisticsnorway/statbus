"use client";
import { TableHead } from "@/components/ui/table";
import { ReactNode, ThHTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import { useSearchSorting } from "@/atoms/search";

interface SortableTableHeadProps
  extends ThHTMLAttributes<HTMLTableCellElement> {
  readonly name: string;
  readonly label?: string;
  readonly children?: ReactNode;
}

export default function SortableTableHead({
  children,
  name,
  label,
  ...props
}: SortableTableHeadProps) {
  const { sorting, updateSorting } = useSearchSorting();

  const handleSort = () => {
    let newDirection: 'asc' | 'desc' | 'desc.nullslast' = 'asc';
    if (sorting.field === name) {
      newDirection = sorting.direction === 'asc' ? 'desc.nullslast' : 'asc';
    }
    updateSorting(name, newDirection);
    // executeSearch is no longer needed here; the URL sync hook will trigger it.
  };

  return (
    <TableHead {...props}>
      <button
        onClick={handleSort}
        className={cn("p-0", sorting.field === name ? "underline" : "")}
      >
        {label}
      </button>
      {children}
    </TableHead>
  );
}
