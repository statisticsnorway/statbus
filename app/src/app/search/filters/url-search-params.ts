import { generateFTSQuery } from "@/app/search/generate-fts-query";
import { SearchAction } from "../search";
import { Tables } from "@/lib/database.types";

export const SEARCH = "search";

function buildPathQuery(values: (string | null | undefined)[]): string | null {
  const path = values[0];
  if (path=== undefined) {
    return null;
  }
  if (path === null || path === '' || path === 'null') {
    return "is.null";
  }
  return `cd.${path}`;
}

function parseInitialValues(initialValue: string | null): (string | null)[] {
  return initialValue?.split(",").map(value => {
    if (value === '' || value === 'null') {
      return null;
    }
    return value;
  }) ?? [];
}

export function fullTextSearchDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(SEARCH);
  return fullTextSearchDeriveStateUpdateFromValue(initialValue);
}

export function fullTextSearchDeriveStateUpdateFromValue(value: string | null): SearchAction {
  return {
    type: "set_query",
    payload: {
      app_param_name: SEARCH,
      api_param_name: SEARCH,
      api_param_value: value ? `fts(simple).${generateFTSQuery(value)}` : null,
      app_param_values: value ? [value] : [],
    },
  };
}

export const UNIT_TYPE = "unit_type";

export function unitTypeDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(UNIT_TYPE);
  const initialValues = parseInitialValues(initialValue);
  return unitTypeDeriveStateUpdateFromValues(initialValues);
}

const unitTypebuildQuery = (values: (string | null)[]) => {
  return values.length ? `in.(${values.join(",")})` : null;
};
export function unitTypeDeriveStateUpdateFromValues(values: (string | null)[]): SearchAction {
  let result = {
    type: "set_query",
    payload: {
      app_param_name: UNIT_TYPE,
      api_param_name: UNIT_TYPE,
      api_param_value: values == null ? null : unitTypebuildQuery(values),
      app_param_values: values,
    },
  } as SearchAction;
  return result;
}


export const INVALID_CODES = "invalid_codes";

export function invalidCodesDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(INVALID_CODES);
  return invalidCodesDeriveStateUpdateFromValues(initialValue);
}

export function invalidCodesDeriveStateUpdateFromValues(value: (string | null)): SearchAction {
  let result = {
    type: "set_query",
    payload: {
      app_param_name: INVALID_CODES,
      api_param_name: INVALID_CODES,
      api_param_value: value === "yes" ? `not.is.null` : null,
      app_param_values: value !== null ? [value] : [],
    },
  } as SearchAction;
  return result;
}


export const LEGAL_FORM = "legal_form_code";
export function legalFormDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(LEGAL_FORM);
  const initialValues = parseInitialValues(initialValue);
  return legalFormDeriveStateUpdateFromValues(initialValues);
}

export function legalFormDeriveStateUpdateFromValues(values: (string | null)[]): SearchAction {
  let result = {
    type: "set_query",
    payload: {
      app_param_name: LEGAL_FORM,
      api_param_name: LEGAL_FORM,
      api_param_value: values.length ? `in.(${values.join(",")})` : null,
      app_param_values: values,
    },
  } as SearchAction;
  return result;
}


export const REGION = "physical_region_path";

export function regionDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(REGION);
  const initialValues = parseInitialValues(initialValue);
  return regionDeriveStateUpdateFromValues(initialValues);
}

export function regionDeriveStateUpdateFromValues(values: (string | null)[]): SearchAction {
  let result = {
    type: "set_query",
    payload: {
      app_param_name: REGION,
      api_param_name: REGION,
      api_param_value: buildPathQuery(values),
      app_param_values: values,
    },
  } as SearchAction;
  return result;
}


export const SECTOR = "sector_path";

export function sectorDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(SECTOR);
  const initialValues = parseInitialValues(initialValue);
  return sectorDeriveStateUpdateFromValues(initialValues);
}

export function sectorDeriveStateUpdateFromValues(values: (string | null)[]): SearchAction {
  let result = {
    type: "set_query",
    payload: {
      app_param_name: SECTOR,
      api_param_name: SECTOR,
      api_param_value: buildPathQuery(values),
      app_param_values: values,
    },
  } as SearchAction;
  return result;
}


export const ACTIVITY_CATEGORY_PATH = "primary_activity_category_path";

export function activityCategoryDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams): SearchAction {
  const initialValue = urlSearchParams.get(ACTIVITY_CATEGORY_PATH);
  const initialValues = parseInitialValues(initialValue);
  return activityCategoryDeriveStateUpdateFromValues(initialValues);
}

export function activityCategoryDeriveStateUpdateFromValues(values: (string | null)[]): SearchAction {
  let result = {
    type: "set_query",
    payload: {
      app_param_name: ACTIVITY_CATEGORY_PATH,
      api_param_name: ACTIVITY_CATEGORY_PATH,
      api_param_value: buildPathQuery(values),
      app_param_values: values,
    },
  } as SearchAction;
  return result;
}


export const DATA_SOURCE = "data_source";

export function dataSourceDeriveStateUpdateFromSearchParams(urlSearchParams: URLSearchParams, dataSources: Tables<"data_source">[]): SearchAction {
  const initialValue = urlSearchParams.get(DATA_SOURCE);
  const initialValues = parseInitialValues(initialValue);
  return dataSourceDeriveStateUpdateFromValues(initialValues, dataSources);
}

export function dataSourceDeriveStateUpdateFromValues(values: (string | null)[], dataSources: Tables<"data_source">[]): SearchAction {
  const codeToIdMap = new Map(dataSources.map(ds => [ds.code, ds.id]));
  const ids = values
    .filter(value => value !== null) // Remove null values
    .map(value => codeToIdMap.get(value))
    .filter(id => id !== undefined); // Remove undefined ids (in case of unmatched codet)

  const searchAction = {
    type: "set_query",
    payload: {
      app_param_name: DATA_SOURCE,
      api_param_name: "data_source_ids",
      api_param_value: ids.length ? `cs.{${ids.join(",")}}` : null,
      app_param_values: values,
    },
  } as SearchAction;
  return searchAction;
}


export function externalIdentDeriveStateUpdateFromSearchParams(
  maybeDefaultExternalIdentType: Tables<"external_ident_type_ordered">,
  urlSearchParams: URLSearchParams
): SearchAction {
  const initialValue = maybeDefaultExternalIdentType ? urlSearchParams.get(maybeDefaultExternalIdentType.code!) : null;
  return externalIdentDeriveStateUpdateFromValues(maybeDefaultExternalIdentType, initialValue);
}

export function externalIdentDeriveStateUpdateFromValues(
  maybeDefaultExternalIdentType: Tables<"external_ident_type_ordered">,
  value: (string | null)
): SearchAction {
  let result = maybeDefaultExternalIdentType &&
    {
      type: "set_query",
      payload: {
        app_param_name: maybeDefaultExternalIdentType.code,
        api_param_name: `external_idents->>${maybeDefaultExternalIdentType.code}`,
        api_param_value: value ? `eq.${value}` : null,
        app_param_values: value ? [value] : [],
      },
    } as SearchAction;
  return result;
}


/**
 * Parses a raw string value into an object containing the operator and operand.
 *
 * Supports parsing of various operator formats, including:
 * - Standard format: 'operator.operand'
 * - 'in' format with parentheses: 'in.(operand1, operand2, ...)'
 *
 * @param {string | null} rawValue - The raw string input to be parsed.
 *   - Example: 'eq.100', 'gt.50', 'in.(10,20,30)'
 *
 * @returns {{ operator: string; operand: string } | null}
 *   - An object with `operator` and `operand` properties if parsing is successful.
 *   - Returns `null` if the input is `null` or does not match the expected pattern.
 */
export function statisticalVariableParse(rawValue: string | null): { operator: string; operand: string } | null {
  if (rawValue == null) {
    return null;
  }

  // Regex for 'in.(...)' format
  const inRegex = /^(?<operator>in)\.\((?<operand>.*)\)$/;
  const inMatch = rawValue.match(inRegex);
  if (inMatch?.groups) {
    return { operator: inMatch.groups.operator, operand: inMatch.groups.operand };
  }

  // Regex for standard 'operator.operand' format
  const standardRegex = /^(?<operator>[^.]+)\.(?<operand>[^()]+)$/;
  const standardMatch = rawValue.match(standardRegex);
  if (standardMatch?.groups) {
    return { operator: standardMatch.groups.operator, operand: standardMatch.groups.operand };
  }

  // Return null if no regex matches
  return null;
}


export function statisticalVariablesDeriveStateUpdateFromSearchParams(
  statDefinitions: Tables<"stat_definition_ordered">[],
  urlSearchParams: URLSearchParams
): SearchAction[] {
  let result = statDefinitions.map(statDefinition => {
    const initialValue = urlSearchParams.get(statDefinition.code!);
    var parsedInitialValue = statisticalVariableParse(initialValue);
    var stateAction = parsedInitialValue == null ? null :
      statisticalVariableDeriveStateUpdateFromValue(statDefinition, parsedInitialValue);
    return stateAction;
  }).filter(stateAction => !!stateAction);
  return result;
}

export function statisticalVariableDeriveStateUpdateFromValue(
  statDefinition: Tables<"stat_definition_ordered">,
  value: {operator: string, operand: string} | null,
): SearchAction  {
  let apiParamValue = null;
  let appParamValues = [];

  if (value) {
    if (value.operator === "in") {
      // Assume the operand is a comma-separated string, and format it accordingly
      const formattedOperand = `(${value.operand})`;
      apiParamValue = `${value.operator}.${formattedOperand}`;
      appParamValues.push(apiParamValue);
    } else {
      apiParamValue = `${value.operator}.${value.operand}`;
      appParamValues.push(apiParamValue);
    }
  }

  let result =
    {
      type: "set_query",
      payload: {
        app_param_name: statDefinition.code,
        api_param_name: `stats_summary->${statDefinition.code}->sum`,
        api_param_value: apiParamValue,
        app_param_values: appParamValues,
      },
    } as SearchAction;
  return result;
}
