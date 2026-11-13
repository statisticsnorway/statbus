import {
  PHYSICAL_LOCATION,
  physicalLocationDeriveStateUpdateFromSearchParams,
} from "@/app/search/filters/url-search-params";

// A location's country is required, so a unit has a physical location exactly
// when statistical_unit.physical_country_id is set (STATBUS-625).
describe("the physical location search filter", () => {
  const derive = (query: string) =>
    physicalLocationDeriveStateUpdateFromSearchParams(new URLSearchParams(query));

  it("lists units without a physical location", () => {
    expect(derive(`${PHYSICAL_LOCATION}=missing`)).toEqual({
      type: "set_query",
      payload: {
        app_param_name: "physical_location",
        api_param_name: "physical_country_id",
        api_param_value: "is.null",
        app_param_values: ["missing"],
      },
    });
  });

  it("lists units with one", () => {
    expect(derive(`${PHYSICAL_LOCATION}=present`)).toMatchObject({
      payload: { api_param_value: "not.is.null", app_param_values: ["present"] },
    });
  });

  it("filters nothing when absent", () => {
    expect(derive("")).toMatchObject({ payload: { api_param_value: null, app_param_values: [] } });
  });
});
