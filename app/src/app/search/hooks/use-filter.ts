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
      type: "options",
      name: "physical_region_id",
      label: "Region",
      options: regions.map(({code, name}) => (
        {
          label: `${code} ${name}`,
          value: code ?? ""
        }
      )),
      selected: [],
      postgrestQuery: ({selected}) => `in.(${selected.join(',')})`
    },
    {
      type: "options",
      name: "primary_activity_category_code",
      label: "Activity Category",
      options: activityCategories.map(({code, label, name}) => (
        {
          label: `${label} ${name}`,
          value: code ?? ""
        }
      )),
      selected: [],
      postgrestQuery: ({selected}) => `in.(${selected.join(',')})`
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
