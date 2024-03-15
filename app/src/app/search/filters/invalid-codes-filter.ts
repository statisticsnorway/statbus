export const INVALID_CODES: SearchFilterName = "invalid_codes";

export const createInvalidCodesFilter = (
  params: URLSearchParams
): SearchFilter => {
  const value = params.get(INVALID_CODES);
  return {
    type: "radio",
    name: INVALID_CODES,
    label: "Import Issues",
    options: [
      {
        label: "Yes",
        value: "yes",
        humanReadableValue: "Yes",
      },
    ],
    selected: value ? [value === "null" ? null : value] : [],
  };
};
