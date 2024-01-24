import {Dispatch} from "react";
import {Input} from "@/components/ui/input";
import {OptionsFilter} from "@/app/search/components/OptionsFilter";
import {ResetFilterButton} from "@/app/search/components/ResetFilterButton";
import {ConditionalFilter} from "@/app/search/components/ConditionalFilter";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";

interface TableToolbarProps {
  readonly filters: SearchFilter[],
  readonly dispatch: Dispatch<SearchFilterActions>
}

export default function TableToolbar({filters, dispatch}: TableToolbarProps) {
  const hasFilterSelected = filters.some(({selected}) => selected.length > 0)

  const createFilterComponent = (filter: SearchFilter) => {
    switch (filter.type) {
      case "options":
        return <OptionsFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      case "conditional":
        return <ConditionalFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      case "search":
        return <SearchFilterComponent key={filter.name} filter={filter} dispatch={dispatch}/>;
      default:
        return null;
    }
  }

  return (
    <div className="flex items-center flex-wrap -m-2 space-x-2">
      {filters.map(createFilterComponent)}
      {hasFilterSelected && <ResetFilterButton onReset={() => dispatch({type: "reset_all"})}/>}
    </div>
  )
}

function SearchFilterComponent({filter: {name, label}, dispatch}: {
  filter: SearchFilter,
  dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <Input
      type="text"
      id="search-prompt"
      placeholder={label}
      className="w-[150px] h-10 ml-2"
      onChange={(e) => {
        dispatch({type: "set", payload: {name, value: e.target.value.trim()}})
      }}
    />
  )
}

function ConditionalFilterComponent({filter: {name, label, condition, selected}, dispatch}: {
  filter: SearchFilter,
  dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <ConditionalFilter
      title={label}
      selected={{condition, value: selected[0]}}
      onChange={({condition, value}) => dispatch({type: "set", payload: {name, value, condition}})}
      onReset={() => dispatch({type: "reset", payload: {name}})}
    />
  )
}

function OptionsFilterComponent({filter: {name, label, options, selected}, dispatch}: {
  filter: SearchFilter,
  dispatch: Dispatch<SearchFilterActions>
}) {
  return (
    <OptionsFilter
      title={label}
      options={options}
      selectedValues={selected}
      onToggle={({value}) => dispatch({type: "toggle", payload: {name, value}})}
      onReset={() => dispatch({type: "reset", payload: {name}})}
    />
  )
}

