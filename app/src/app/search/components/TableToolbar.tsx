import {Dispatch} from "react";
import {Input} from "@/components/ui/input";
import {TableFilter} from "@/app/search/components/TableFilter";

interface TableToolbarProps {
  readonly onSearch: (search: string) => void,
  readonly filter: SearchFilter,
  readonly dispatch: Dispatch<SearchFilterAction>
}

export default function TableToolbar({filter, dispatch, onSearch}: TableToolbarProps) {
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
        <TableFilter
          title="Activity Category"
          options={filter.activityCategoryOptions}
          selectedOptionValues={filter.activityCategories}
          onToggle={({value}) => dispatch({type: "toggleActivityCategory", payload: value})}
          onReset={() => dispatch({type: "resetActivityCategories", payload: ""})}
        />
        <TableFilter
          title="Region"
          options={filter.regionOptions}
          selectedOptionValues={filter.regions}
          onToggle={({value}) => dispatch({type: "toggleRegion", payload: value})}
          onReset={() => dispatch({type: "resetRegions", payload: ""})}
        />
      </div>
    </div>
  )
}
