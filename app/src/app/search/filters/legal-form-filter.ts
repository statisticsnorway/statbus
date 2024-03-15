import { Tables } from "@/lib/database.types";

export const LEGAL_FORM_CODE: SearchFilterName = "legal_form_code";

export const creatLegalFormFilter = (
  params: URLSearchParams,
  legalForms: Tables<"legal_form">[]
): SearchFilter => {
  const legalFormCode = params.get(LEGAL_FORM_CODE);
  return {
    type: "options",
    name: LEGAL_FORM_CODE,
    label: "Legal Form",
    options: [
      ...legalForms.map(({ code, name }) => ({
        label: `${code} ${name}`,
        value: code,
      })),
    ],
    selected: legalFormCode?.split(",") ?? [],
  };
};
