import {Dispatch} from "react";
import {Input} from "@/components/ui/input";
import {TableFilter} from "@/app/search/components/TableFilter";
import {ResetFilterButton} from "@/app/search/components/ResetFilterButton";

interface TableToolbarProps {
  readonly onSearch: (search: string) => void,
  readonly filters: SearchFilter[],
  readonly dispatch: Dispatch<SearchFilterAction>
}

export default function TableToolbar(
  {
    filters,
    dispatch,
    onSearch
  }: TableToolbarProps) {

  const hasFilterSelected = filters.some(({selected}) => selected.length > 0)

  return (
    <div className="flex items-center flex-wrap -m-2 space-x-2">
      <Input
        type="text"
        id="search-prompt"
        placeholder="Name"
        className="w-[150px] h-full m-2"
        onChange={(e) => onSearch(e.target.value.trim())}
      />
      {
        filters.map(({name, label, options, selected}) => (
          <TableFilter
            key={name}
            title={label}
            options={options}
            selectedValues={selected}
            onToggle={({value}) => dispatch({type: "toggle", payload: {name, value}})}
            onReset={() => dispatch({type: "reset", payload: {name, value: ""}})}
          />
        ))
      }
      {
        hasFilterSelected && (
          <ResetFilterButton onReset={() => dispatch({type: "reset_all"})}/>
        )
      }
    </div>
  )
}

