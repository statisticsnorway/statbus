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

type SearchFilterActionTypes =
  "toggleRegion"
  | "toggleActivityCategory"
  | "resetRegions"
  | "resetActivityCategories";

type SearchFilterAction = { type: SearchFilterActionTypes; payload: any };
