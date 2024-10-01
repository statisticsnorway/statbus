import { Badge } from "@/components/ui/badge";
import * as React from "react";
import { ConditionalValue } from "../search";

export function ConditionalValueBadge({ operator, value }: ConditionalValue) {
  function resolveSymbol(condition: string) {
    switch (condition) {
      case "eq":
        return "";
      case "gt":
        return ">";
      case "lt":
        return "<";
      case "in":
        return "in";
      default:
        return "";
    }
  }

  const prefix = resolveSymbol(operator);

  return (
    <Badge variant="secondary" className="rounded-sm px-2 font-normal">
      {prefix} {value}
    </Badge>
  );
}
