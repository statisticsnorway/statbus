export function createFilters(opts: FilterOptions, params: URLSearchParams): SearchFilter[] {
  const unit_type: SearchFilterName = 'unit_type'
  const physical_region_path: SearchFilterName = 'physical_region_path'
  const primary_activity_category_path: SearchFilterName = 'primary_activity_category_path'
  const tax_reg_ident: SearchFilterName = 'tax_reg_ident'
  const search: SearchFilterName = 'search'
  const sector_code: SearchFilterName = 'sector_code'
  const unitTypeUrlParamValue = getURLSearchParamValue(params, unit_type)
  const searchUrlParamValue = getURLSearchParamValue(params, search)
  const taxRegIdentUrlParamValue = getURLSearchParamValue(params, tax_reg_ident)
  const regionUrlParamValue = getURLSearchParamValue(params, physical_region_path)
  const sectorCodeUrlParamValue = getURLSearchParamValue(params, sector_code)
  const activityCategoryCodeUrlParamValue = getURLSearchParamValue(params, primary_activity_category_path)

  const standardFilters: SearchFilter[] = [
    {
      type: "search",
      label: "Name",
      name: search,
      operator: "fts",
      selected: searchUrlParamValue ? [searchUrlParamValue] : [],
    },
    {
      type: "search",
      label: "Tax ID",
      name: tax_reg_ident,
      operator: "eq",
      selected: taxRegIdentUrlParamValue ? [taxRegIdentUrlParamValue] : [],
    },
    {
      type: "options",
      label: "Type",
      name: unit_type,
      operator: "in",
      options: [
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-100"
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-100"
        },
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-100"
        }
      ],
      selected: unitTypeUrlParamValue?.split(',') ?? ['legal_unit', 'establishment', 'enterprise'],
    },
    {
      type: "radio",
      name: physical_region_path,
      label: "Region",
      operator: "cd",
      options: [
        {
          label: "Not Set",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200"
        },
        ...opts.regions.map(({code, path, name}) => (
          {
            label: `${code} ${name}`,
            value: path as string,
            humanReadableValue: `${code} ${name}`
          }
        ))],
      selected: regionUrlParamValue ? [regionUrlParamValue] : [],
    },
    {
      type: "options",
      name: 'sector_code',
      label: "Sector",
      operator: "in",
      options: [
        ...opts.sectors.map(({code, name}) => (
          {
            label: `${code} ${name}`,
            value: code
          }
        ))],
      selected: sectorCodeUrlParamValue?.split(',') ?? [],
    },
    {
      type: "radio",
      name: primary_activity_category_path,
      label: "Activity Category",
      operator: "cd",
      options: [
        {
          label: "Not Set",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200"
        },
        ...opts.activityCategories.map(({code, path, name}) => (
          {
            label: `${code} ${name}`,
            value: path as string,
            humanReadableValue: `${code} ${name}`
          }
        ))],
      selected: activityCategoryCodeUrlParamValue ? [activityCategoryCodeUrlParamValue] : [],
    }
  ];

  // @ts-ignore - we do not know what will be the statistical variable names
  const statisticalVariableFilters: SearchFilter[] = opts.statisticalVariables.map(variable => {
    const param = params?.get(variable.code)
    const [operator, value] = param?.split('.') ?? []
    return {
      type: "conditional",
      name: variable.code,
      label: variable.name,
      selected: value ? [value] : [],
      operator
    }
  });

  return [...standardFilters, ...statisticalVariableFilters]
}

const getURLSearchParamValue = (params: URLSearchParams, name: SearchFilterName): string | null => {
  const searchFilterURLParam = params.get(name)
  if (!searchFilterURLParam) {
    return null
  }

  const dotIndex = searchFilterURLParam.indexOf('.')
  return dotIndex > -1 ? searchFilterURLParam.substring(dotIndex + 1) : null
}
