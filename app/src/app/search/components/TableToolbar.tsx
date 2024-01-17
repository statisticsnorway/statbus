import {Dispatch} from "react";
import {Input} from "@/components/ui/input";
import {TableFilter} from "@/app/search/components/TableFilter";
import {ResetFilterButton} from "@/app/search/components/ResetFilterButton";

interface TableToolbarProps {
  readonly onSearch: (search: string) => void,
  readonly filter: SearchFilter,
  readonly dispatch: Dispatch<SearchFilterAction>
}

export default function TableToolbar(
  {
    filter: {
      selectedRegions,
      selectedActivityCategories,
      activityCategoryOptions,
      regionOptions
    },
    dispatch,
    onSearch
  }: TableToolbarProps) {

  const hasFilterSelected = selectedActivityCategories.length > 0 || selectedRegions.length > 0

  return (
    <div className="flex items-center flex-wrap space-x-2 h-10">
      <Input
        type="text"
        id="search-prompt"
        placeholder="Name"
        className="w-[150px] h-full"
        onChange={(e) => onSearch(e.target.value.trim())}
      />
      <TableFilter
        title="Activity Category"
        options={activityCategoryOptions}
        selectedValues={selectedActivityCategories}
        onToggle={({value}) => dispatch({type: "toggleActivityCategory", payload: value})}
        onReset={() => dispatch({type: "resetActivityCategories", payload: ""})}
      />
      <TableFilter
        title="Region"
        options={regionOptions}
        selectedValues={selectedRegions}
        onToggle={({value}) => dispatch({type: "toggleRegion", payload: value})}
        onReset={() => dispatch({type: "resetRegions", payload: ""})}
      />
      {
        hasFilterSelected && (
          <ResetFilterButton onReset={() => dispatch({type: "reset", payload: ""})}/>
        )
      }
    </div>
  )
}

