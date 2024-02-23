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

export const useFilter = (filters: SearchFilter[][]) => {
  const [standardFilters, statisticalVariableFilters, others] = filters
  return useReducer(searchFilterReducer, [...standardFilters, ...statisticalVariableFilters, ...others])
}

