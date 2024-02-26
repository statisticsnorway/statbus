import {TableHead} from "@/components/ui/table";
import {ReactNode, ThHTMLAttributes} from "react";
import {useSearchContext} from "@/app/search/search-provider";
import {cn} from "@/lib/utils";

type SortableTableHeadProps = ThHTMLAttributes<HTMLTableCellElement> & {
  name: string
  children: ReactNode
};

export default function SortableTableHead({children, name, ...props}: SortableTableHeadProps) {
  const {order, searchOrderDispatch } = useSearchContext();
  const isActive = order.name === name;
  return (
    <TableHead
      {...props}
      className={cn(props.className, 'cursor-pointer', isActive ? 'underline' : '')}
      onClick={() => searchOrderDispatch({type: 'set_order', payload: {name}})}
    >
      {children}
    </TableHead>
  )
}
