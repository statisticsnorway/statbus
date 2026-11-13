import { changedCells } from "./history-changes";

// A history row says what changed from the row above it; the rest repeats.
describe("changedCells", () => {
  const keys = [(r: { name: string; size: string | null }) => r.name, (r: { name: string; size: string | null }) => r.size];

  it("marks every cell of the first row as changed", () => {
    expect(changedCells([{ name: "A", size: "s" }], keys)).toEqual([[true, true]]);
  });

  it("marks only the cells that differ from the row above", () => {
    expect(
      changedCells(
        [
          { name: "A", size: "s" },
          { name: "B", size: "s" },
          { name: "B", size: null },
        ],
        keys
      )
    ).toEqual([
      [true, true],
      [true, false],
      [false, true],
    ]);
  });

  it("compares objects by their content", () => {
    const k = [(r: { region: { code: string } }) => r.region];
    expect(changedCells([{ region: { code: "1" } }, { region: { code: "1" } }], k)).toEqual([[true], [false]]);
  });
});

describe("changedCells without a key", () => {
  it("always shows a column that has no key (the row's own date)", () => {
    expect(changedCells([{ a: 1 }, { a: 1 }], [undefined, (r: { a: number }) => r.a])).toEqual([
      [true, true],
      [true, false],
    ]);
  });
});
