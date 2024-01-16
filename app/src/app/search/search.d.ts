type SearchFilterOption = {
  readonly label: string
  readonly value: string
}

type SearchFilter = {
  selectedRegions: string[]
  selectedActivityCategories: string[],
  regionOptions: SearchFilterOption[],
  activityCategoryOptions: SearchFilterOption[]
};

type SearchFilterActionTypes =
  "toggleRegion"
  | "toggleActivityCategory"
  | "resetRegions"
  | "resetActivityCategories";

type SearchFilterAction = { type: SearchFilterActionTypes; payload: any };
