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
  getStatisticalUnitsEstimatedCount: jest.fn(),
  getStatisticalUnitsExactCount: jest.fn(),
}));

import { derivedApiSearchParamsAtom, filtersAtom } from "./search";
import {
  QUALITY,
  qualityDeriveStateUpdateFromSearchParams,
} from "../app/search/filters/url-search-params";

// xz3jej: a Data quality card links to /search?unit_type=legal_unit&quality=<check>. The search
// turns that parameter into the inner embed of the check's table public.quality_<check>, the
// same one the card counts with.
describe("quality search filter", () => {
  it("reads a known check from the URL", () => {
    const action = qualityDeriveStateUpdateFromSearchParams(
      new URLSearchParams(
        "unit_type=legal_unit&quality=establishment_activity_differs"
      )
    );
    expect(action).toEqual({
      type: "set_query",
      payload: {
        app_param_name: QUALITY,
        api_param_name: "select",
        api_param_value: "*,quality_establishment_activity_differs!inner()",
        app_param_values: ["establishment_activity_differs"],
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
        api_param_name: "select",
        api_param_value: null,
        app_param_values: [],
      },
    });
  });

  it("sends the check's inner embed to PostgREST with the other filters", () => {
    const store = createStore();
    store.set(filtersAtom, {
      unit_type: ["legal_unit"],
      [QUALITY]: ["establishment_activity_differs"],
    });
    const params = store.get(derivedApiSearchParamsAtom);
    expect(params.get("select")).toBe(
      "*,quality_establishment_activity_differs!inner()"
    );
    expect(params.get("unit_type")).toBe("in.(legal_unit)");
    expect(params.get("existence_from")).toBe("lte.2026-11-18");
    expect(params.get("existence_until")).toBe("gt.2026-11-18");
  });

  it("sends no select once the check is cleared", () => {
    const store = createStore();
    store.set(filtersAtom, { unit_type: ["legal_unit"], [QUALITY]: [] });
    const params = store.get(derivedApiSearchParamsAtom);
    expect(params.has("select")).toBe(false);
    expect(params.get("unit_type")).toBe("in.(legal_unit)");
  });
});
