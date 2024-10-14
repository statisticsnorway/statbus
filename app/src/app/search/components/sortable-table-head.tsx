"use client";
import { TableHead } from "@/components/ui/table";
import { ReactNode, ThHTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import { useSearchContext } from "@/app/search/use-search-context";

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
  const {
    searchState: { order },
    modifySearchState,
  } = useSearchContext();
  return (
    <TableHead {...props}>
      <button
        onClick={() => modifySearchState({ type: "set_order", payload: { name } })}
        className={cn("p-0", order.name === name ? "underline" : "")}
      >
        {label}
      </button>
      {children}
    </TableHead>
  );
}
