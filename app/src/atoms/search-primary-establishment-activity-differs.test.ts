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
  PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS,
  PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS_SELECT,
  primaryEstablishmentActivityDiffersDeriveStateUpdateFromSearchParams,
} from "../app/search/filters/url-search-params";

// xz3jej: the dashboard card links to
// /search?unit_type=legal_unit&primary_establishment_activity_differs=true. The search turns
// that parameter into the inner embed of the report table, the same one the card counts with.
describe("primary_establishment_activity_differs search filter", () => {
  it("reads the app parameter from the URL", () => {
    const action =
      primaryEstablishmentActivityDiffersDeriveStateUpdateFromSearchParams(
        new URLSearchParams(
          "unit_type=legal_unit&primary_establishment_activity_differs=true"
        )
      );
    expect(action).toEqual({
      type: "set_query",
      payload: {
        app_param_name: PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS,
        api_param_name: "select",
        api_param_value: "*,primary_establishment_activity_differs!inner()",
        app_param_values: ["true"],
      },
    });
  });

  it("sends the inner embed to PostgREST with the other filters", () => {
    const store = createStore();
    store.set(filtersAtom, {
      unit_type: ["legal_unit"],
      [PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS]: ["true"],
    });
    const params = store.get(derivedApiSearchParamsAtom);
    expect(params.get("select")).toBe(
      PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS_SELECT
    );
    expect(params.get("unit_type")).toBe("in.(legal_unit)");
    expect(params.get("existence_from")).toBe("lte.2026-11-18");
    expect(params.get("existence_until")).toBe("gt.2026-11-18");
  });

  it("sends no select once the filter is cleared", () => {
    const store = createStore();
    store.set(filtersAtom, {
      unit_type: ["legal_unit"],
      [PRIMARY_ESTABLISHMENT_ACTIVITY_DIFFERS]: [],
    });
    const params = store.get(derivedApiSearchParamsAtom);
    expect(params.has("select")).toBe(false);
    expect(params.get("unit_type")).toBe("in.(legal_unit)");
  });
});
