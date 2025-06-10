"use client";
import { TableHead } from "@/components/ui/table";
import { ReactNode, ThHTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import { useSearch } from "@/atoms/hooks";

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
  const { searchState, updateSorting, executeSearch } = useSearch();
  const { sorting } = searchState;

  const handleSort = async () => {
    let newDirection: 'asc' | 'desc' = 'asc';
    if (sorting.field === name) {
      newDirection = sorting.direction === 'asc' ? 'desc' : 'asc';
    }
    updateSorting(name, newDirection);
    await executeSearch();
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
