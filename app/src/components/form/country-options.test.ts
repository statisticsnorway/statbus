import { countryOptions } from "./country-options";

// The country lists on the edit forms (postal and physical location): the
// installation's own country (settings.country_id) first, the rest by name.
const countries = [
  { id: 3, name: "Albania" },
  { id: 1, name: "Afghanistan" },
  { id: 9, name: "Norway" },
  { id: 2, name: "Åland Islands" },
];

describe("countryOptions", () => {
  it("puts the domestic country first and keeps the rest in name order", () => {
    expect(countryOptions(countries, 9)).toEqual([
      { value: 9, label: "Norway" },
      { value: 1, label: "Afghanistan" },
      { value: 2, label: "Åland Islands" },
      { value: 3, label: "Albania" },
    ]);
  });

  it("lists every country by name when no domestic country is configured", () => {
    expect(countryOptions(countries, null).map((o) => o.label)).toEqual([
      "Afghanistan",
      "Åland Islands",
      "Albania",
      "Norway",
    ]);
  });
});
