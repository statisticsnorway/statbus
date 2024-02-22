import {FilterOptions, SearchFilter, SearchFilterCondition, SearchFilterName} from "@/app/search/search.types";

export function createFilters(opts: FilterOptions, urlSearchParams: URLSearchParams): [SearchFilter[], SearchFilter[]] {
  const unit_type: SearchFilterName = 'unit_type'
  const physical_region_path: SearchFilterName = 'physical_region_path'
  const primary_activity_category_path: SearchFilterName = 'primary_activity_category_path'
  const tax_reg_ident: SearchFilterName = 'tax_reg_ident'
  const search: SearchFilterName = 'search'
  const defaultUnitTypeFilterValue = 'enterprise'
  const standardFilters: SearchFilter[] = [
    {
      type: "search",
      label: "Name",
      // Search is a vector field of name indexed for fast full text search.
      name: search,
      selected: urlSearchParams?.has(search) ? [urlSearchParams?.get(search) as string] : [],
    },
    {
      type: "search",
      label: "Tax ID",
      name: tax_reg_ident,
      selected: urlSearchParams?.has(tax_reg_ident) ? [urlSearchParams?.get(tax_reg_ident) as string] : [],
    },
    {
      type: "options",
      label: "Type",
      name: unit_type,
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
      selected: urlSearchParams?.get(unit_type)?.split(',') ?? [defaultUnitTypeFilterValue],
    },
    {
      type: "radio",
      name: physical_region_path,
      label: "Region",
      options: opts.regions.map(({code, path, name}) => (
        {
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`
        }
      )),
      selected: urlSearchParams?.has(physical_region_path) ? [urlSearchParams?.get(physical_region_path) as string] : [],
    },
    {
      type: "radio",
      name: primary_activity_category_path,
      label: "Activity Category",
      options: opts.activityCategories.map(({code, path, name}) => (
        {
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`
        }
      )),
      selected: urlSearchParams?.has(primary_activity_category_path) ? [urlSearchParams?.get(primary_activity_category_path) as string] : [],
    }
  ];

  // @ts-ignore - we do not know what will be the statistical variable names
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
