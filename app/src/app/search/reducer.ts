import {Dispatch} from "react";

type SearchFilterOption = {
  readonly label: string
  readonly value: string
}

type SearchFilter = {
  regions: string[]
  activityCategories: string[],
  regionOptions: SearchFilterOption[],
  activityCategoryOptions: SearchFilterOption[]
};

enum SearchFilterActionTypes {
  ToggleRegion = "toggleRegion",
  ToggleActivityCategory = "toggleActivityCategory",
  ResetRegions = "resetRegions",
  ResetActivityCategories = "resetActivityCategories",
  SetActivityCategoryOptions = "setActivityCategoryOptions",
  SetRegionOptions = "setRegionOptions"
}

type SearchFilterAction = { type: SearchFilterActionTypes; payload: any };

export function searchFilterReducer(state: SearchFilter, {type, payload}: SearchFilterAction): SearchFilter {
  switch (type) {
    case SearchFilterActionTypes.SetActivityCategoryOptions:
      return {...state, activityCategoryOptions: payload}
    case SearchFilterActionTypes.SetRegionOptions:
      return {...state, regionOptions: payload}
    case SearchFilterActionTypes.ToggleRegion:
      return {
        ...state,
        regions: state.regions.includes(payload)
          ? state.regions.filter(id => id !== payload)
          : [...state.regions, payload]
      }
    case SearchFilterActionTypes.ToggleActivityCategory:
      return {
        ...state,
        activityCategories: state.activityCategories.includes(payload)
          ? state.activityCategories.filter(id => id !== payload)
          : [...state.activityCategories, payload]
      }
    case SearchFilterActionTypes.ResetRegions:
      return {...state, regions: []}
    case SearchFilterActionTypes.ResetActivityCategories:
      return {...state, activityCategories: []}
    default:
      return state
  }
}

export const resetRegions = (dispatch: Dispatch<SearchFilterAction>) => () => {
  dispatch({type: SearchFilterActionTypes.ResetRegions, payload: ""})
}

export const resetActivityCategories = (dispatch: Dispatch<SearchFilterAction>) => () => {
  dispatch({type: SearchFilterActionTypes.ToggleActivityCategory, payload: ""})
}

export const toggleRegion = (dispatch: Dispatch<SearchFilterAction>) => (option: { label: string, value: string }) => {
  dispatch({type: SearchFilterActionTypes.ToggleRegion, payload: option.value})
}

export const toggleActivityCategory = (dispatch: Dispatch<SearchFilterAction>) => (option: {
  label: string,
  value: string
}) => {
  dispatch({type: SearchFilterActionTypes.ToggleActivityCategory, payload: option.value})
}
