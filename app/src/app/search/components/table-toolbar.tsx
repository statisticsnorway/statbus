import {Dispatch, useCallback} from "react";
import {Input} from "@/components/ui/input";
import {OptionsFilter} from "@/app/search/components/options-filter";
import {ResetFilterButton} from "@/app/search/components/reset-filter-button";
import {ConditionalFilter} from "@/app/search/components/conditional-filter";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";

interface TableToolbarProps {
  readonly filters: SearchFilter[],
  readonly dispatch: Dispatch<SearchFilterActions>
}

export default function TableToolbar({filters, dispatch}: TableToolbarProps) {
  const hasFilterSelected = filters.some(({selected}) => selected?.[0]?.toString().length)

  const createFilterComponent = useCallback((filter: SearchFilter) => {
    switch (filter.type) {
      case "radio":
        return <RadioFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      case "options":
        return <OptionsFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      case "conditional":
        return <ConditionalFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      case "search":
        return <SearchFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      default:
        return null;
    }
  }, [dispatch])

  return (
    <div className="flex items-center flex-wrap -m-2 space-x-2">
      {filters.map(createFilterComponent)}
      {hasFilterSelected && <ResetFilterButton className="h-10 m-2" onReset={() => dispatch({type: "reset_all"})}/>}
    </div>
  )
}

function SearchFilterComponent({filter: {name, label, selected}, dispatch}: {
  readonly filter: SearchFilter,
  readonly dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <Input
      type="text"
      id={`search-prompt-${name}`}
      placeholder={label}
      className="w-[100px] h-10 ml-2"
      value={selected[0] ?? ""}
      onChange={(e) => {
        dispatch({type: "set_search", payload: {name, value: e.target.value.trim()}})
      }}
    />
  )
}

function ConditionalFilterComponent({filter: {name, label, condition, selected}, dispatch}: {
  readonly filter: SearchFilter,
  readonly dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <ConditionalFilter
      title={label}
      selected={{condition, value: selected[0]}}
      onChange={({condition, value}) => dispatch({type: "set_condition", payload: {name, value, condition}})}
      onReset={() => dispatch({type: "reset", payload: {name}})}
    />
  )
}

function OptionsFilterComponent({filter: {name, label, options, selected}, dispatch}: {
  readonly filter: SearchFilter,
  readonly dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <OptionsFilter
      title={label}
      options={options}
      selectedValues={selected}
      onToggle={({value}) => dispatch({type: "toggle_option", payload: {name, value}})}
      onReset={() => dispatch({type: "reset", payload: {name}})}
    />
  )
}

function RadioFilterComponent({filter: {name, label, options, selected}, dispatch}: {
  readonly filter: SearchFilter,
  readonly dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <OptionsFilter
      title={label}
      options={options}
      selectedValues={selected}
      onToggle={({value}) => dispatch({type: "toggle_radio_option", payload: {name, value}})}
      onReset={() => dispatch({type: "reset", payload: {name}})}
    />
  )
}

