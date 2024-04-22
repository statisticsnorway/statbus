import { Dispatch, ReactNode, ThHTMLAttributes } from "react";
import { useRegionContext } from "./use-region-context";
import { TableHead } from "@/components/ui/table";
import { cn } from "@/lib/utils";

interface RegionSortableTableHeadProps
  extends ThHTMLAttributes<HTMLTableCellElement> {
  readonly name: string;
  readonly children: ReactNode;
}

export default function RegionSortableTableHead({
  name,
  children,
  ...props
}: RegionSortableTableHeadProps) {
  const {
    regions: { order },
    dispatch,
  } = useRegionContext();
  return (
    <TableHead {...props}>
      <button
        onClick={() => dispatch({ type: "set_order", payload: { name } })}
        className={cn("p-0", order.name === name ? "underline" : "")}
      >
        {children}
      </button>
    </TableHead>
  );
}
