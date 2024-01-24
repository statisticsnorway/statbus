import {Dispatch} from "react";
import {Input} from "@/components/ui/input";
import {TableFilter} from "@/app/search/components/TableFilter";
import {ResetFilterButton} from "@/app/search/components/ResetFilterButton";
import {StatisticalVariablesFilter} from "@/app/search/components/StatisticalVariablesFilter";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";

interface TableToolbarProps {
  readonly filters: SearchFilter[],
  readonly dispatch: Dispatch<SearchFilterActions>
}

export default function TableToolbar(
  {
    filters,
    dispatch
  }: TableToolbarProps) {

  const hasFilterSelected = filters.some(({selected}) => selected.length > 0)

  return (
    <div className="flex items-center flex-wrap -m-2 space-x-2">

      {
        filters.map(({type, name, label, options, selected, condition}) => {
            switch (type) {
              case "standard":
                return (
                  <TableFilter
                    key={name}
                    title={label}
                    options={options}
                    selectedValues={selected}
                    onToggle={({value}) => dispatch({type: "toggle", payload: {name, value}})}
                    onReset={() => dispatch({type: "reset", payload: {name}})}
                  />
                );
              case "statistical_variable":
                return (
                  <StatisticalVariablesFilter
                    key={name}
                    title={label}
                    selected={{condition, value: selected[0]}}
                    onChange={({condition, value}) => dispatch({type: "set", payload: {name, value, condition}})}
                    onReset={() => dispatch({type: "reset", payload: {name}})}
                  />
                );
              case "search":
                return (
                  <Input
                    key={name}
                    type="text"
                    id="search-prompt"
                    placeholder={label}
                    className="w-[150px] h-10 ml-2"
                    onChange={(e) => {
                      dispatch({type: "set", payload: {name, value: e.target.value.trim()}})
                    }}
                  />
                );
            }
          }
        )
      }
      {
        hasFilterSelected && (
          <ResetFilterButton onReset={() => dispatch({type: "reset_all"})}/>
        )
      }
    </div>
  )
}

