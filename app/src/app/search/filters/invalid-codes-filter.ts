import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const INVALID_CODES: SearchFilterName = "invalid_codes";

export const createInvalidCodesFilter = (
  params: URLSearchParams
): SearchFilter => {
  const [value] = createURLParamsResolver(params)(INVALID_CODES);
  return {
    type: "radio",
    name: INVALID_CODES,
    label: "Import Issues",
    options: [
      {
        label: "No",
        value: null,
        humanReadableValue: "No",
      },
      {
        label: "Yes",
        value: "yes",
        humanReadableValue: "Yes",
      },
    ],
    selected: value ? [value === "null" ? null : value] : [],
  };
};
