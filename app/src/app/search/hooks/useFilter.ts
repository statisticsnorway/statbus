import {Tables} from "@/lib/database.types";
import {useReducer} from "react";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";

function searchFilterReducer(state: SearchFilter[], action: SearchFilterActions): SearchFilter[] {
    switch (action.type) {
        case "toggle":
            return state.map(f =>
                f.name === action.payload?.name ? {
                    ...f,
                    selected: f.selected.includes(action.payload.value)
                        ? f.selected.filter(id => id !== action.payload.value)
                        : [...f.selected, action.payload.value]
                } : f
            )
        case "set":
            return state.map(f =>
                f.name === action.payload?.name
                    ? {...f, selected: [action.payload.value], condition: action.payload.condition ?? null}
                    : f
            )
        case "reset":
            return state.map(f =>
                f.name === action.payload?.name
                    ? {...f, selected: []}
                    : f
            )
        case "reset_all":
            return state.map(f =>
                ({...f, selected: []})
            )
        default:
            return state
    }
}

interface FilterOptions {
    activityCategories: Tables<"activity_category_available">[],
    regions: Tables<"region">[]
    statisticalVariables: Tables<"stat_definition">[]
}

export const useFilter = ({regions = [], activityCategories = [], statisticalVariables = []}: FilterOptions) => {
    const standardFilters: SearchFilter[] = [
        {
            type: "standard",
            name: "region_codes",
            label: "Region",
            options: regions.map(({code, name}) => (
                {
                    label: `${code} ${name}`,
                    value: code ?? ""
                }
            )),
            selected: [],
            condition: "in"
        },
        {
            type: "standard",
            name: "activity_category_codes",
            label: "Activity Category",
            options: activityCategories.map(({label, name}) => (
                {
                    label: `${label} ${name}`,
                    value: label ?? ""
                }
            )),
            selected: [],
            condition: "in"
        }
    ];

    const statisticalVariableFilters: SearchFilter[] = statisticalVariables.map(variable => ({
        type: "statistical_variable",
        name: variable.code,
        label: variable.name,
        selected: [],
        condition: null
    }));

    return useReducer(searchFilterReducer, [...standardFilters, ...statisticalVariableFilters])
}
