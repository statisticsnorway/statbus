import { codeListOptions, groupRuns } from "./code-list-options";

// A code list (sector, legal form, region, unit size) as a select's options.
describe("codeListOptions", () => {
  // Sectors are a tree (path DOMESTIC.A.1110): the inner nodes have no code and
  // group the coded leaves under them.
  const sectorTree = [
    { id: 37, path: "DOMESTIC", code: null, name: "Domestic sectors" },
    { id: 39, path: "DOMESTIC.B", code: null, name: "Financial corporations" },
    { id: 51, path: "DOMESTIC.B.3200", code: "3200", name: "Banks" },
    {
      id: 38,
      path: "DOMESTIC.A",
      code: null,
      name: "Non-financial corporations",
    },
    {
      id: 43,
      path: "DOMESTIC.A.1110",
      code: "1110",
      name: "Public enterprises",
    },
    { id: 67, path: "REST", code: null, name: "Rest of the world" },
    { id: 69, path: "REST.F.9000", code: "9000", name: "Rest of the world" },
  ];

  it("offers a tree's coded rows in path order, each under its uncoded ancestors as group title", () => {
    expect(codeListOptions(sectorTree, { optional: true })).toEqual([
      { value: "", label: "None", disabled: false },
      {
        value: 43,
        label: "1110 Public enterprises",
        disabled: false,
        group: "Domestic sectors › Non-financial corporations",
      },
      {
        value: 51,
        label: "3200 Banks",
        disabled: false,
        group: "Domestic sectors › Financial corporations",
      },
      {
        value: 69,
        label: "9000 Rest of the world",
        disabled: false,
        group: "Rest of the world",
      },
    ]);
  });

  it("keeps a coded inner node choosable (a region with sub-regions)", () => {
    const regions = [
      { id: 2, path: "1.045", code: "1045", name: "Denmark" },
      { id: 1, path: "1", code: "1", name: "Europe" },
    ];
    expect(codeListOptions(regions).map((o) => [o.label, o.group])).toEqual([
      ["1 Europe", undefined],
      ["1045 Denmark", undefined],
    ]);
  });

  it("starts an optional list with None, which stores no value", () => {
    expect(codeListOptions(sectorTree, { optional: true })[0]).toEqual({
      value: "",
      label: "None",
      disabled: false,
    });
  });

  it("labels by name alone when the list shows no codes (unit size)", () => {
    expect(
      codeListOptions([{ id: 2, code: "med", name: "Medium" }], {
        showCode: false,
      })
    ).toEqual([{ value: 2, label: "Medium", disabled: false }]);
  });

  it("draws the options as runs under their group titles, None in an untitled run", () => {
    const runs = groupRuns(codeListOptions(sectorTree, { optional: true }));
    expect(
      runs.map((run) => [run.title, run.options.map((o) => o.value)])
    ).toEqual([
      [undefined, [""]],
      ["Domestic sectors › Non-financial corporations", [43]],
      ["Domestic sectors › Financial corporations", [51]],
      ["Rest of the world", [69]],
    ]);
  });
});
