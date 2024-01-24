import {Tables} from "@/lib/database.types";
import {useReducer} from "react";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";

function searchFilterReducer(state: SearchFilter[], action: SearchFilterActions): SearchFilter[] {
  switch (action.type) {
    case "toggle":
      return state.map(f =>
        f.name === action.payload?.name ? {
          ...f,
          selected: f.selected.includes(action.payload.value)
            ? f.selected.filter(id => id !== action.payload.value)
            : [...f.selected, action.payload.value]
        } : f
      )
    case "set":
      return state.map(f =>
        f.name === action.payload?.name
          ? {...f, selected: [action.payload.value], condition: action.payload.condition}
          : f
      )
    case "reset":
      return state.map(f =>
        f.name === action.payload?.name
          ? {...f, selected: []}
          : f
      )
    case "reset_all":
      return state.map(f =>
        ({...f, selected: []})
      )
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
      options: [],
      selected: [],
      postgrestQuery: ({selected}) => `ilike.*${selected[0]}*`
    },
    {
      type: "search",
      label: "ID",
      name: "tax_reg_ident",
      options: [],
      selected: [],
      postgrestQuery: ({selected}) => `eq.${selected[0]}`
    },
    {
      type: "options",
      name: "region_codes",
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
          label: `${label} ${name} (${code})`,
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
