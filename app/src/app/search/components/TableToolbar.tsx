import {Input} from "@/components/ui/input";
import {Table} from "@tanstack/table-core";
import {TableFilter} from "@/app/search/components/TableFilter";

interface TableToolbarProps<TData> {
  table: Table<TData>
  readonly onSearch: (search: string) => void
}

export default function TableToolbar<TData>({table, onSearch}: TableToolbarProps<TData>) {

  const options = {
    categories: [
      { label: "Fishing", value: "A011" },
      { label: "Growing of tobacco", value: "A0115" },
      { label: "Extraction of natural gas", value: "B0520" },
      { label: "Manufacture of watches and clocks", value: "C1052" },
    ],
    regions: [
      { label: "Vestland", value: "norway-w" },
      { label: "Rogaland", value: "norway-w2" },
    ]
  }

  return (
    <div className="flex items-center justify-between">
      <div className="flex flex-1 items-center space-x-2 h-10">
        <Input
          type="text"
          id="search-prompt"
          placeholder="Find units by name"
          className="w-[150px] lg:w-[250px] h-full"
          onChange={(e) => onSearch(e.target.value)}
        />
        <TableFilter title="Activity Category" options={options.categories} selected={new Set(["A0115", "B0520"])} />
        <TableFilter title="Region" options={options.regions} selected={new Set(["norway-w"])} />
      </div>
    </div>
  )
}
