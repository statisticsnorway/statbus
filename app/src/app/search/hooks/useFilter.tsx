import {Tables} from "@/lib/database.types";
import {useReducer} from "react";
import {searchFilterReducer} from "@/app/search/reducer";

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
