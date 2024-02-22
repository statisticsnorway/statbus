import {FilterOptions, SearchFilter, SearchFilterCondition} from "@/app/search/search.types";
import {PHYSICAL_REGION_PATH, PRIMARY_ACTIVITY_CATEGORY_PATH} from "@/app/search/constants";

export function createFilters(opts: FilterOptions, urlSearchParams: URLSearchParams): [SearchFilter[], SearchFilter[]] {
  const standardFilters: SearchFilter[] = [
    {
      type: "search",
      label: "Name",
      // Search is a vector field of name indexed for fast full text search.
      name: "search",
      selected: urlSearchParams?.has('search') ? [urlSearchParams?.get('search') as string] : [],
    },
    {
      type: "search",
      label: "Tax ID",
      name: "tax_reg_ident",
      selected: urlSearchParams?.has('tax_reg_ident') ? [urlSearchParams?.get('tax_reg_ident') as string] : [],
    },
    {
      type: "options",
      label: "Type",
      name: "unit_type",
      options: [
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-200"
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-200"
        },
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-200"
        }
      ],
      selected: urlSearchParams?.get('unit_type')?.split(',') ?? ["enterprise"],
    },
    {
      type: "radio",
      name: "physical_region_path",
      label: "Region",
      options: opts.regions.map(({code, path, name}) => (
        {
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`
        }
      )),
      selected: urlSearchParams?.has(PHYSICAL_REGION_PATH) ? [urlSearchParams?.get(PHYSICAL_REGION_PATH) as string] : [],
    },
    {
      type: "radio",
      name: "primary_activity_category_path",
      label: "Activity Category",
      options: opts.activityCategories.map(({code, path, name}) => (
        {
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`
        }
      )),
      selected: urlSearchParams?.has(PRIMARY_ACTIVITY_CATEGORY_PATH) ? [urlSearchParams?.get(PRIMARY_ACTIVITY_CATEGORY_PATH) as string] : [],
    }
  ];

  const statisticalVariableFilters: SearchFilter[] = opts.statisticalVariables.map(variable => {
    const conditionalSearchParam = urlSearchParams?.get(variable.code)
    const [condition, value] = conditionalSearchParam?.split('.') ?? []

    return {
      type: "conditional",
      name: variable.code,
      label: variable.name,
      selected: value ? [value] : [],
      condition: condition ? condition as SearchFilterCondition : undefined
    }
  });

  return [standardFilters, statisticalVariableFilters]
}
