import {Tables} from "@/lib/database.types";
import {useReducer} from "react";

function searchFilterReducer(state: SearchFilter, {type, payload}: SearchFilterAction): SearchFilter {
  const {selectedRegions, selectedActivityCategories} = state;
  switch (type) {
    case "toggleRegion":
      return {
        ...state,
        selectedRegions: selectedRegions.includes(payload)
          ? selectedRegions.filter(id => id !== payload)
          : [...selectedRegions, payload]
      }
    case "toggleActivityCategory":
      return {
        ...state,
        selectedActivityCategories: selectedActivityCategories.includes(payload)
          ? selectedActivityCategories.filter(id => id !== payload)
          : [...selectedActivityCategories, payload]
      }
    case "reset": {
      return {
        ...state,
        selectedRegions: [],
        selectedActivityCategories: []
      }
    }
    case "resetRegions":
      return {
        ...state,
        selectedRegions: []
      }
    case "resetActivityCategories":
      return {
        ...state,
        selectedActivityCategories: []
      }
    default:
      return state
  }
}

export const useFilter = (activityCategories: Tables<"activity_category_available">[], regions: Tables<"region">[]) => {
  return useReducer(searchFilterReducer, {
    selectedRegions: [],
    selectedActivityCategories: [],
    activityCategoryOptions: activityCategories.map(({label, name}) =>
      ({label: `${label} ${name}`, value: label ?? ""})),
    regionOptions: regions.map(({code, name}) =>
      ({label: `${code} ${name}`, value: code ?? ""}))
  })
}
