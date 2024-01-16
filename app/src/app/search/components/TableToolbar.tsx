import {useReducer} from "react";
import {Input} from "@/components/ui/input";
import {TableFilter} from "@/app/search/components/TableFilter";
import {
  resetActivityCategories,
  resetRegions,
  searchFilterReducer,
  toggleActivityCategory,
  toggleRegion
} from "@/app/search/reducer";

interface TableToolbarProps {
  readonly onSearch: (search: string) => void
}

export default function TableToolbar({onSearch}: TableToolbarProps) {
  const [searchFilter, dispatch] = useReducer(
    searchFilterReducer,
    {
      regions: [],
      activityCategories: [],
      activityCategoryOptions: [
        {label: "Fishing", value: "A011"},
        {label: "Growing of tobacco", value: "A0115"},
        {label: "Extraction of natural gas", value: "B0520"},
        {label: "Manufacture of watches and clocks", value: "C1052"},
      ],
      regionOptions: [
        {label: "Vestland", value: "norway-w"},
        {label: "Rogaland", value: "norway-w2"},
      ]
    });

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
          options={searchFilter.activityCategoryOptions}
          selectedOptionValues={searchFilter.activityCategories}
          onToggle={toggleActivityCategory(dispatch)}
          onReset={resetActivityCategories(dispatch)}
        />
        <TableFilter
          title="Region"
          options={searchFilter.regionOptions}
          selectedOptionValues={searchFilter.regions}
          onToggle={toggleRegion(dispatch)}
          onReset={resetRegions(dispatch)}
        />
      </div>
    </div>
  )
}
