import { atom, createStore } from "jotai";

jest.mock("./app", () => {
  const { atom: makeAtom } = jest.requireActual("jotai");
  return {
    selectedTimeFrameAtom: makeAtom({ valid_on: "2026-11-18" }),
    searchStateInitializedAtom: makeAtom(true),
  };
});
jest.mock("./rest-client", () => ({ restClientAtom: atom(null) }));
jest.mock("./base-data", () => {
  const { atom: makeAtom } = jest.requireActual("jotai");
  return {
    externalIdentTypesAtom: makeAtom([]),
    statDefinitionsAtom: makeAtom([]),
    useBaseData: () => ({}),
  };
});
jest.mock("../app/search/search-requests", () => ({
  getStatisticalUnitsData: jest.fn(),
  getStatisticalUnitsExactCount: jest.fn(),
}));

import { derivedApiSearchParamsAtom, filtersAtom } from "./search";
import {
  QUALITY,
  qualityDeriveStateUpdateFromSearchParams,
} from "../app/search/filters/url-search-params";

// 05pe0x: a Data quality card links to /search?unit_type=...&quality=<rule>[:<stat code>]. The search
// carries the check as the API parameter quality_check, which search-requests.ts resolves by the
// check's count into the PostgREST resource (app/search/quality-search.ts, its own tests).
describe("quality search filter", () => {
  it("reads a check without a variable from the URL", () => {
    const action = qualityDeriveStateUpdateFromSearchParams(
      new URLSearchParams("unit_type=legal_unit&quality=establishment_activity_differs")
    );
    expect(action).toEqual({
      type: "set_query",
      payload: {
        app_param_name: QUALITY,
        api_param_name: "quality_check",
        api_param_value: "establishment_activity_differs",
        app_param_values: ["establishment_activity_differs"],
      },
    });
  });

  it("reads a per-variable check with its variable code from the URL", () => {
    const action = qualityDeriveStateUpdateFromSearchParams(
      new URLSearchParams("unit_type=legal_unit&quality=establishments_above_legal_unit:employees")
    );
    expect(action).toEqual({
      type: "set_query",
      payload: {
        app_param_name: QUALITY,
        api_param_name: "quality_check",
        api_param_value: "establishments_above_legal_unit:employees",
        app_param_values: ["establishments_above_legal_unit:employees"],
      },
    });
  });

  it("ignores a check it does not know", () => {
    const action = qualityDeriveStateUpdateFromSearchParams(
      new URLSearchParams("quality=no_such_check")
    );
    expect(action).toEqual({
      type: "set_query",
      payload: {
        app_param_name: QUALITY,
        api_param_name: "quality_check",
        api_param_value: null,
        app_param_values: [],
      },
    });
  });

  it("sends the check with the other filters and the time frame", () => {
    const store = createStore();
    store.set(filtersAtom, {
      unit_type: ["legal_unit", "establishment"],
      [QUALITY]: ["missing_region"],
    });
    const params = store.get(derivedApiSearchParamsAtom);
    expect(params.get("quality_check")).toBe("missing_region");
    expect(params.has("select")).toBe(false);
    expect(params.get("unit_type")).toBe("in.(legal_unit,establishment)");
    expect(params.get("existence_from")).toBe("lte.2026-11-18");
    expect(params.get("existence_until")).toBe("gt.2026-11-18");
  });

  it("sends no check once it is cleared", () => {
    const store = createStore();
    store.set(filtersAtom, { unit_type: ["legal_unit"], [QUALITY]: [] });
    const params = store.get(derivedApiSearchParamsAtom);
    expect(params.has("quality_check")).toBe(false);
    expect(params.get("unit_type")).toBe("in.(legal_unit)");
  });
});
