import {
  PHYSICAL_COUNTRY,
  physicalCountryDeriveStateUpdateFromSearchParams,
} from "@/app/search/filters/url-search-params";

// The Regions map's "View and download" for a foreign country lists the units located there
// (z2qt08), by statistical_unit.physical_country_id.
describe("the physical country search filter", () => {
  const derive = (query: string) =>
    physicalCountryDeriveStateUpdateFromSearchParams(new URLSearchParams(query));

  it("lists the units located in one country", () => {
    expect(derive(`${PHYSICAL_COUNTRY}=214`)).toEqual({
      type: "set_query",
      payload: {
        app_param_name: "physical_country",
        api_param_name: "physical_country_id",
        api_param_value: "in.(214)",
        app_param_values: ["214"],
      },
    });
  });

  it("lists the units located in any of several countries", () => {
    expect(derive(`${PHYSICAL_COUNTRY}=214,215`)).toMatchObject({
      payload: { api_param_value: "in.(214,215)", app_param_values: ["214", "215"] },
    });
  });

  it("filters nothing when absent or not a country id", () => {
    const none = {
      type: "set_query",
      payload: { app_param_name: "physical_country", api_param_name: "physical_country_id", api_param_value: null, app_param_values: [] },
    };
    expect([derive(""), derive(`${PHYSICAL_COUNTRY}=SE`)]).toEqual([none, none]);
  });
});
