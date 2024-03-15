import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const TAX_REG_IDENT: SearchFilterName = "tax_reg_ident";

export const createTaxRegIdentFilter = (
  params: URLSearchParams
): SearchFilter => {
  const [taxRegIdent] = createURLParamsResolver(params)(TAX_REG_IDENT);
  return {
    type: "search",
    label: "Tax ID",
    name: TAX_REG_IDENT,
    operator: "eq",
    selected: taxRegIdent ? [taxRegIdent] : [],
  };
};
