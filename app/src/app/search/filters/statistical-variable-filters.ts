import { Tables } from "@/lib/database.types";
import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const createStatisticalVariableFilters = (
  params: URLSearchParams,
  statisticalVariables: Tables<"stat_definition">[]
): SearchFilter[] => {
  // @ts-ignore - the name of statistical variables are not known at compile time
  return statisticalVariables.map((variable) => {
    const [value, operator] = createURLParamsResolver(params)(variable.code);
    return {
      type: "conditional",
      name: variable.code,
      label: variable.name,
      selected: value ? [value] : [],
      operator: operator,
    };
  });
};
