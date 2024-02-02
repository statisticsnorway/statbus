import {Tables} from "@/lib/database.types";
import {useReducer} from "react";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";

function searchFilterReducer(state: SearchFilter[], action: SearchFilterActions): SearchFilter[] {
  switch (action.type) {
    case "toggle_option": {
      const {name, value} = action.payload
      return state.map(f =>
        f.name === name ? {
          ...f,
          selected: f.selected.includes(value) ? f.selected.filter(id => id !== value) : [...f.selected, value]
        } : f
      )
    }
    case "toggle_radio_option": {
      const {name, value} = action.payload
      return state.map(f => f.name === name ? {...f, selected: f.selected.find(id => id == value) ? [] : [value]} : f)
    }
    case "set_condition": {
      const {name, value, condition} = action.payload
      return state.map(f => f.name === name ? {...f, selected: [value], condition} : f)
    }
    case "set_search": {
      const {name, value} = action.payload
      return state.map(f => f.name === name ? {...f, selected: [value]} : f)
    }
    case "reset": {
      const {name} = action.payload
      return state.map(f => f.name === name ? {...f, selected: []} : f)
    }
    case "reset_all":
      return state.map(f => ({...f, selected: []}))
    default:
      return state
  }
}

interface FilterOptions {
  activityCategories: Tables<"activity_category_available">[],
  regions: Tables<"region">[]
  statisticalVariables: Tables<"stat_definition">[]
}

export const useFilter = ({regions = [], activityCategories = [], statisticalVariables = []}: FilterOptions) => {
  const standardFilters: SearchFilter[] = [
    {
      type: "search",
      label: "Name",
      name: "name",
      selected: [],
      postgrestQuery: ({selected}) => `ilike.*${selected[0]}*`
    },
    {
      type: "search",
      label: "Tax ID",
      name: "tax_reg_ident",
      selected: [],
      postgrestQuery: ({selected}) => `eq.${selected[0]}`
    },
    {
      type: "radio",
      name: "physical_region_path",
      label: "Region",
      options: regions.map(({path, name}) => (
        {
          label: `${path} ${name}`,
          value: path as string,
          humanReadableValue: name
        }
      )),
      selected: [],
      postgrestQuery: ({selected}) => `cd.${selected.join()}`
    },
    {
      type: "radio",
      name: "primary_activity_category_path",
      label: "Activity Category",
      options: activityCategories.map(({path, name}) => (
        {
          label: `${path} ${name}`,
          value: path as string,
          humanReadableValue: name?.toString()
        }
      )),
      selected: [],
      postgrestQuery: ({selected}) => `cd.${selected.join()}`
    }
  ];

  const statisticalVariableFilters: SearchFilter[] = statisticalVariables.map(variable => ({
    type: "conditional",
    name: variable.code,
    label: variable.name,
    selected: [],
    postgrestQuery: ({condition, selected}: SearchFilter) => `${condition}.${selected.join(',')}`
  }));

  return useReducer(searchFilterReducer, [...standardFilters, ...statisticalVariableFilters])
}
