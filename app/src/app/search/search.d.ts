type SearchFilterCondition = "eq" | "gt" | "lt" | "in" | "ilike"

type SearchFilterName =
  "search"
  | "tax_reg_ident"
  | "unit_type"
  | "physical_region_path"
  | "primary_activity_category_path"

type SearchFilterOption = {
  readonly label: string
  readonly value: string | null
  readonly humanReadableValue?: string
  readonly className?: string
}

type SearchOrder = {
  readonly name: string
  readonly direction: string
}

interface SearchState {
  readonly filters: SearchFilter[];
  readonly order: SearchOrder;
}

type SearchFilter = {
  readonly type: "options" | "radio" | "conditional" | "search"
  readonly name: SearchFilterName
  readonly label: string
  readonly options?: SearchFilterOption[]
  readonly selected: (string | null)[]
  readonly condition?: SearchFilterCondition
}

type SearchResult = {
  statisticalUnits: Tables<"statistical_unit">[]
  count: number
}

interface ConditionalValue {
  condition: SearchFilterCondition
  value: string,
}

interface ToggleOption {
  type: "toggle_option",
  payload: {
    name: string,
    value: string | null
  }
}

interface SetOrder {
  type: "set_order",
  payload: {
    name: string
  }
}

interface ToggleRadioOption {
  type: "toggle_radio_option",
  payload: {
    name: string,
    value: string | null
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

type SearchAction = ToggleOption | ToggleRadioOption | SetCondition | SetSearch | Reset | ResetAll | SetOrder

interface FilterOptions {
  activityCategories: Tables<"activity_category_available">[],
  regions: Tables<"region_used">[]
  statisticalVariables: Tables<"stat_definition">[]
}

type SetOrderAction = { type: "set_order", payload: { name: string } }