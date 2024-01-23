export type LegalUnit = {
    tax_reg_ident: string | null,
    name: string | null
}

export type SearchFilterValue = string | number

export type SearchFilterCondition = "eq" | "gt" | "lt" | "in"

export type SearchFilterOption = {
    readonly label: string
    readonly value: SearchFilterValue
}

export type SearchFilter = {
    readonly type: "standard" | "statistical_variable"
    readonly name: string
    readonly label: string
    readonly options?: SearchFilterOption[]
    readonly selected: SearchFilterValue[]
    readonly condition: SearchFilterCondition | null
}

export type SearchResult = {
    legalUnits: LegalUnit[]
    count: number
}

export interface ConditionalValue {
    condition: SearchFilterCondition
    value: SearchFilterValue,
}

interface Toggle {
    type: "toggle",
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
        condition: SearchFilterCondition
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
