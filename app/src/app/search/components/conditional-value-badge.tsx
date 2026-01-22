import { Badge } from "@/components/ui/badge";
import * as React from "react";
import { ConditionalValue, Condition } from "../search";

interface ConditionalValueBadgeProps {
  value: ConditionalValue;
}

export function ConditionalValueBadge({ value }: ConditionalValueBadgeProps) {
  function resolveSymbol(operator: string) {
    switch (operator) {
      case "eq":
        return "=";
      case "gt":
        return ">";
      case "gte":
        return "≥";
      case "lt":
        return "<";
      case "lte":
        return "≤";
      case "in":
        return "∈";
      default:
        return operator;
    }
  }

  function formatCondition(condition: Condition): string {
    const symbol = resolveSymbol(condition.operator);
    return `${symbol}${condition.operand}`;
  }

  // Handle both single and multiple conditions
  const displayText = 'conditions' in value 
    ? value.conditions.map(formatCondition).join(' AND ')
    : formatCondition(value);

  return (
    <Badge variant="secondary" className="rounded-sm px-2 font-normal">
      {displayText}
    </Badge>
  );
}
