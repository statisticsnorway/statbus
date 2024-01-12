import {Input} from "@/components/ui/input";
import {Table} from "@tanstack/table-core";

interface TableToolbarProps<TData> {
  table: Table<TData>
  readonly onSearch: (search: string) => void
}

export default function TableToolbar<TData>({table, onSearch}: TableToolbarProps<TData>) {
  return (
    <div className="flex items-center justify-between">
      <div className="flex flex-1 items-center space-x-2">
        <Input
          type="text"
          id="search-prompt"
          placeholder="Find units by name"
          className="h-8 w-[150px] lg:w-[250px]"
          onChange={(e) => onSearch(e.target.value)}
        />
      </div>
    </div>
  )
}
