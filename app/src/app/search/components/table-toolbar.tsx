import {useCallback} from "react";
import {Input} from "@/components/ui/input";
import {OptionsFilter} from "@/app/search/components/options-filter";
import {ResetFilterButton} from "@/app/search/components/reset-filter-button";
import {ConditionalFilter} from "@/app/search/components/conditional-filter";
import type {SearchFilter} from "@/app/search/search.types";
import {useSearchContext} from "@/app/search/search-provider";

export default function TableToolbar() {
  const {filters, dispatch} = useSearchContext()
  const hasAnyFilterSelected = filters.some(({selected}) => selected?.[0]?.toString().length)

  const createFilterComponent = useCallback(({type, name, label, options, selected, condition}: SearchFilter) => {
    switch (type) {
      case "radio":
        return (
          <OptionsFilter
            title={label}
            options={options}
            selectedValues={selected}
            onToggle={({value}) => dispatch({type: "toggle_radio_option", payload: {name, value}})}
            onReset={() => dispatch({type: "reset", payload: {name}})}
          />
        );
      case "options":
        return (
          <OptionsFilter
            title={label}
            options={options}
            selectedValues={selected}
            onToggle={({value}) => dispatch({type: "toggle_option", payload: {name, value}})}
            onReset={() => dispatch({type: "reset", payload: {name}})}
          />
        );
      case "conditional":
        return (
          <ConditionalFilter
            title={label}
            selected={{condition, value: selected[0]}}
            onChange={({condition, value}) => dispatch({type: "set_condition", payload: {name, value, condition}})}
            onReset={() => dispatch({type: "reset", payload: {name}})}
          />
        );
      case "search":
        return (
          <Input
            type="text"
            id={`search-prompt-${name}`}
            placeholder={label}
            className="w-[100px] h-10 ml-2"
            value={selected[0] ?? ""}
            onChange={(e) => {
              dispatch({type: "set_search", payload: {name, value: e.target.value}})
            }}
          />
        );
      default:
        return null;
    }
  }, [dispatch])

  return (
    <div className="flex items-center flex-wrap -m-2 space-x-2">
      {filters.map(createFilterComponent)}
      {hasAnyFilterSelected && <ResetFilterButton className="h-10 m-2" onReset={() => dispatch({type: "reset_all"})}/>}
    </div>
  )
}

