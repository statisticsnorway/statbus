import { codeListOptions } from "./code-list-options";

// A code list (sector, legal form, region, unit size) as a select's options.
describe("codeListOptions", () => {
  const sectors = [
    { id: 37, code: null, name: "Domestic sectors" },
    { id: 38, code: null, name: "Non-financial corporations" },
    { id: 43, code: "1110", name: "Public unincorporated enterprises owned by central government" },
  ];

  it("labels a row by its code and name, a row without a code by its name", () => {
    expect(codeListOptions(sectors).map((o) => o.label)).toEqual([
      "Domestic sectors",
      "Non-financial corporations",
      "1110 Public unincorporated enterprises owned by central government",
    ]);
  });

  it("offers a row without a code as a heading only: it groups the coded rows below it", () => {
    expect(codeListOptions(sectors).map((o) => [o.value, o.disabled])).toEqual([
      [37, true],
      [38, true],
      [43, false],
    ]);
  });

  it("starts an optional list with None, which stores no value", () => {
    expect(codeListOptions(sectors, { optional: true })[0]).toEqual({ value: "", label: "None", disabled: false });
  });

  it("labels by name alone when the list shows no codes (unit size)", () => {
    expect(codeListOptions([{ id: 2, code: "med", name: "Medium" }], { showCode: false })).toEqual([
      { value: 2, label: "Medium", disabled: false },
    ]);
  });
});
