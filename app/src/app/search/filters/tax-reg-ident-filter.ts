export const TAX_REG_IDENT: SearchFilterName = "tax_reg_ident";

export const createTaxRegIdentFilter = (
  params: URLSearchParams
): SearchFilter => {
  const taxRegIdent = params.get(TAX_REG_IDENT);
  return {
    type: "search",
    label: "Tax ID",
    name: TAX_REG_IDENT,
    selected: taxRegIdent ? [taxRegIdent] : [],
  };
};
