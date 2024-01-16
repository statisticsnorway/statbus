export function searchFilterReducer(state: SearchFilter, {type, payload}: SearchFilterAction): SearchFilter {
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
