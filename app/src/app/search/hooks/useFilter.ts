import {Tables} from "@/lib/database.types";
import {useReducer} from "react";

function searchFilterReducer(state: SearchFilter[], {
  type,
  payload
}: SearchFilterAction): SearchFilter[] {
  switch (type) {
    case "toggle":
      return state.map(f =>
        f.name === payload?.name ? {
          ...f,
          selected: f.selected.includes(payload.value)
            ? f.selected.filter(id => id !== payload.value)
            : [...f.selected, payload.value]
        } : f
      )
    case "reset":
      return state.map(f => f.name === payload?.name ? {...f, selected: []} : f)
    case "reset_all":
      return state.map(f => ({...f, selected: []}))
    default:
      return state
  }
}

interface FilterOptions {
  activityCategories: Tables<"activity_category_available">[],
  regions: Tables<"region">[]
}

export const useFilter = ({regions = [], activityCategories = []}: FilterOptions) => {
  return useReducer(searchFilterReducer, [
    {
      name: "region_codes",
      label: "Region",
      options: regions.map(({code, name}) => (
        {
          label: `${code} ${name}`,
          value: code ?? ""
        }
      )),
      selected: []
    },
    {
      name: "activity_category_codes",
      label: "Activity Category",
      options: activityCategories.map(({label, name}) => (
        {
          label: `${label} ${name}`,
          value: label ?? ""
        }
      )),
      selected: []
    }
  ])
}
