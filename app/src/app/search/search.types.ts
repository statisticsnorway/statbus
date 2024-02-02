import {Tables} from "@/lib/database.types";

export type SearchFilterValue = string | number

export type SearchFilterCondition = "eq" | "gt" | "lt" | "in" | "ilike"

export type SearchFilterOption = {
    readonly label: string
    readonly value: SearchFilterValue
}

export type SearchFilter = {
    readonly type: "options" | "radio" | "conditional" | "search"
    readonly name: string
    readonly label: string
    readonly options?: SearchFilterOption[]
    readonly selected: SearchFilterValue[]
    readonly condition?: SearchFilterCondition
    readonly postgrestQuery: (filter: SearchFilter) => string
}

export type SearchResult = {
    statisticalUnits: Partial<Tables<"statistical_unit">>[]
    count: number
}

export interface ConditionalValue {
    condition: SearchFilterCondition
    value: SearchFilterValue,
}

interface ToggleOption {
    type: "toggle_option",
    payload: {
        name: string,
        value: SearchFilterValue
    }
}

interface ToggleRadioOption {
  type: "toggle_radio_option",
  payload: {
    name: string,
    value: SearchFilterValue
  }
}

interface SetCondition {
    type: "set_condition",
    payload: {
        name: string,
        value: SearchFilterValue,
        condition: SearchFilterCondition
    }
}

interface SetSearch {
  type: "set_search",
  payload: {
    name: string,
    value: SearchFilterValue
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
