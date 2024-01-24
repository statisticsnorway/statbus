import {Tables} from "@/lib/database.types";

export type SearchFilterValue = string | number

export type SearchFilterCondition = "eq" | "gt" | "lt" | "in" | "ilike"

export type SearchFilterOption = {
    readonly label: string
    readonly value: SearchFilterValue
}

export type SearchFilter = {
    readonly type: "options" | "conditional" | "search"
    readonly name: string
    readonly label: string
    readonly options?: SearchFilterOption[]
    readonly selected: SearchFilterValue[]
    readonly condition?: SearchFilterCondition
    readonly postgrestQuery: (filter: SearchFilter) => string
}

export type SearchResult = {
    legalUnits: Partial<Tables<"legal_unit_region_activity_category_stats_current">>[]
    count: number
}

export interface ConditionalValue {
    condition: SearchFilterCondition
    value: SearchFilterValue,
}

interface Toggle {
    type: "toggle_option",
    payload: {
        name: string,
        value: SearchFilterValue
    }
}

interface Set {
    type: "set",
    payload: {
        name: string,
        value: SearchFilterValue,
        condition?: SearchFilterCondition
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

export type SearchFilterActions = Toggle | Set | Reset | ResetAll
