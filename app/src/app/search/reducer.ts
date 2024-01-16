export function searchFilterReducer(state: SearchFilter, {type, payload}: SearchFilterAction): SearchFilter {
  const {regions, activityCategories} = state;
  switch (type) {
    case "toggleRegion":
      return {
        ...state,
        regions: regions.includes(payload)
          ? regions.filter(id => id !== payload)
          : [...regions, payload]
      }
    case "toggleActivityCategory":
      return {
        ...state,
        activityCategories: activityCategories.includes(payload)
          ? activityCategories.filter(id => id !== payload)
          : [...activityCategories, payload]
      }
    case "resetRegions":
      return {
        ...state,
        regions: []
      }
    case "resetActivityCategories":
      return {
        ...state,
        activityCategories: []
      }
    default:
      return state
  }
}
