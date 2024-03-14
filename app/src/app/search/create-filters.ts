const UNIT_TYPE: SearchFilterName = "unit_type";
const PHYSICAL_REGION_PATH: SearchFilterName = "physical_region_path";
const ACTIVITY_CATEGORY: SearchFilterName = "primary_activity_category_path";
const TAX_REG_IDENT: SearchFilterName = "tax_reg_ident";
const SEARCH: SearchFilterName = "search";
const SECTOR_CODE: SearchFilterName = "sector_code";
const LEGAL_FORM_CODE: SearchFilterName = "legal_form_code";

const createURLParamsResolver =
  (params: URLSearchParams) =>
  (name: string): [string | null, string | null] => {
    const param = params.get(name);
    if (!param) return [null, null];
    const dotIndex = param.indexOf(".");
    const operator = param.substring(0, dotIndex);
    const value = param.substring(dotIndex + 1);
    return [value, operator];
  };

export function createFilters(
  opts: FilterOptions,
  params: URLSearchParams
): SearchFilter[] {
  const resolve = createURLParamsResolver(params);
  const [unitType] = resolve(UNIT_TYPE);
  const [search] = resolve(SEARCH);
  const [taxRegIdent] = resolve(TAX_REG_IDENT);
  const [region] = resolve(PHYSICAL_REGION_PATH);
  const [sectorCode] = resolve(SECTOR_CODE);
  const [legalFormCode] = resolve(LEGAL_FORM_CODE);
  const [activityCategory] = resolve(ACTIVITY_CATEGORY);

  const standardFilters: SearchFilter[] = [
    {
      type: "search",
      label: "Name",
      name: SEARCH,
      operator: "fts",
      selected: search ? [search] : [],
    },
    {
      type: "search",
      label: "Tax ID",
      name: TAX_REG_IDENT,
      operator: "eq",
      selected: taxRegIdent ? [taxRegIdent] : [],
    },
    {
      type: "options",
      label: "Type",
      name: UNIT_TYPE,
      operator: "in",
      options: [
        {
          label: "Legal Unit",
          value: "legal_unit",
          humanReadableValue: "Legal Unit",
          className: "bg-legal_unit-100",
        },
        {
          label: "Establishment",
          value: "establishment",
          humanReadableValue: "Establishment",
          className: "bg-establishment-100",
        },
        {
          label: "Enterprise",
          value: "enterprise",
          humanReadableValue: "Enterprise",
          className: "bg-enterprise-100",
        },
      ],
      selected: unitType?.split(",") ?? [
        "legal_unit",
        "establishment",
        "enterprise",
      ],
    },
    {
      type: "radio",
      name: PHYSICAL_REGION_PATH,
      label: "Region",
      operator: "cd",
      options: [
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...opts.regions.map(({ code, path, name }) => ({
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`,
        })),
      ],
      selected: region ? [region === "null" ? null : region] : [],
    },
    {
      type: "options",
      name: "sector_code",
      label: "Sector",
      operator: "in",
      options: [
        ...opts.sectors.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })),
      ],
      selected: sectorCode?.split(",") ?? [],
    },
    {
      type: "options",
      name: "legal_form_code",
      label: "Legal Form",
      operator: "in",
      options: [
        ...opts.legalForms.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })),
      ],
      selected: legalFormCode?.split(",") ?? [],
    },
    {
      type: "radio",
      name: ACTIVITY_CATEGORY,
      label: "Activity Category",
      operator: "cd",
      options: [
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...opts.activityCategories.map(({ code, path, name }) => ({
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`,
        })),
      ],
      selected: activityCategory
        ? [activityCategory === "null" ? null : activityCategory]
        : [],
    },
  ];

  // @ts-ignore - we do not know what will be the statistical variable names
  const statisticalVariableFilters: SearchFilter[] =
    opts.statisticalVariables.map((variable) => {
      const [value, operator] = resolve(variable.code);
      return {
        type: "conditional",
        name: variable.code,
        label: variable.name,
        selected: value ? [value] : [],
        operator: operator,
      };
    });

  return [...standardFilters, ...statisticalVariableFilters];
}
