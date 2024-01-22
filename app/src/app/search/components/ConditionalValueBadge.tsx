import {Badge} from "@/components/ui/badge";
import * as React from "react";
import type {ConditionalValue, SearchFilterCondition} from "@/app/search/search.types";

export function ConditionalValueBadge({condition, value}: ConditionalValue) {

    function resolveSymbol(condition: SearchFilterCondition) {
        switch (condition) {
            case "equal_to":
                return ""
            case "greater_than":
                return ">"
            case "less_than":
                return "<"
            case "in":
                return "in"
        }
    }

    const prefix = resolveSymbol(condition)

    return (
        <Badge variant="secondary" className="rounded-sm px-1 font-normal">
            {prefix} {value}
        </Badge>
    )
}
