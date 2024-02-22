import {Tables} from "@/lib/database.types";

export type SearchFilterCondition = "eq" | "gt" | "lt" | "in" | "ilike"

export type SearchFilterName =
  "search"
  | "tax_reg_ident"
  | "unit_type"
  | "physical_region_path"
  | "primary_activity_category_path"

export type SearchFilterOption = {
  readonly label: string
  readonly value: string
  readonly humanReadableValue?: string
  readonly className?: string
}

export type SearchFilter = {
  readonly type: "options" | "radio" | "conditional" | "search"
  readonly name: SearchFilterName
  readonly label: string
  readonly options?: SearchFilterOption[]
  readonly selected: string[]
  readonly condition?: SearchFilterCondition
}

export type SearchResult = {
  statisticalUnits: Partial<Tables<"statistical_unit">>[]
  count: number
}

export interface ConditionalValue {
  condition: SearchFilterCondition
  value: string,
}

interface ToggleOption {
  type: "toggle_option",
  payload: {
    name: string,
    value: string
  }
}

interface ToggleRadioOption {
  type: "toggle_radio_option",
  payload: {
    name: string,
    value: string
  }
}

interface SetCondition {
  type: "set_condition",
  payload: {
    name: string,
    value: string,
    condition: SearchFilterCondition
  }
}

interface SetSearch {
  type: "set_search",
  payload: {
    name: string,
    value: string
  }
}

interface Reset {
  type: "reset",
  payload: {
    name: string
  }
}

interface ResetAll {
  type: "reset_all"
}

export type SearchFilterActions = ToggleOption | ToggleRadioOption | SetCondition | SetSearch | Reset | ResetAll

export interface FilterOptions {
  activityCategories: Tables<"activity_category_available">[],
  regions: Tables<"region_used">[]
  statisticalVariables: Tables<"stat_definition">[]
}
