import { Tables } from "@/lib/database.types";
import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const LEGAL_FORM_CODE: SearchFilterName = "legal_form_code";

export const creatLegalFormFilter = (
  params: URLSearchParams,
  legalForms: Tables<"legal_form">[]
): SearchFilter => {
  const [legalFormCode] = createURLParamsResolver(params)(LEGAL_FORM_CODE);
  return {
    type: "options",
    name: LEGAL_FORM_CODE,
    label: "Legal Form",
    operator: "in",
    options: [
      ...legalForms.map(({ code, name }) => ({
        label: `${code} ${name}`,
        value: code,
      })),
    ],
    selected: legalFormCode?.split(",") ?? [],
  };
};
