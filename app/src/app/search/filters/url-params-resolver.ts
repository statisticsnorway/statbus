/**
 * Returns a function that resolves value and operator from a URLSearchParams instance.
 * A param typically looks like this: ?name=in.legal_unit,establishment,enterprise which
 * will resolve to ["legal_unit,establishment,enterprise", "in"]
 * If the parameter is not present, it will return null values for both value and operator
 *
 * @param params URLSearchParams
 */
export const createURLParamsResolver =
  (params: URLSearchParams) =>
  (name: string): [string | null, string | null] => {
    const param = params.get(name);
    if (!param) return [null, null];
    const dotIndex = param.indexOf(".");
    const operator = param.substring(0, dotIndex);
    const value = param.substring(dotIndex + 1);
    return [value, operator];
  };
