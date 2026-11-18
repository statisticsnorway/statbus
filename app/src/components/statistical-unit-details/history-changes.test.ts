import { changedCells } from "./history-changes";

// The history table lists a unit's versions newest first; a row says what
// changed from the version below it, the next older one (cgtb4y).
type Row = { name: string; size: string | null };
const keys = [(r: Row) => r.name, (r: Row) => r.size];

describe("changedCells", () => {
  it("marks every cell of the oldest version as changed", () => {
    expect(changedCells([{ name: "A", size: "s" }], keys, null)).toEqual([[true, true]]);
  });

  it("marks only the cells that differ from the version below", () => {
    expect(
      changedCells(
        [
          { name: "B", size: null },
          { name: "B", size: "s" },
          { name: "A", size: "s" },
        ],
        keys,
        null
      )
    ).toEqual([
      [false, true],
      [true, false],
      [true, true],
    ]);
  });

  it("compares the last row of a page with the next older version, not yet shown", () => {
    expect(
      changedCells(
        [
          { name: "B", size: "m" },
          { name: "B", size: "s" },
        ],
        keys,
        { name: "A", size: "s" }
      )
    ).toEqual([
      [false, true],
      [true, false],
    ]);
  });

  it("compares objects by their content", () => {
    const k = [(r: { region: { code: string } }) => r.region];
    expect(changedCells([{ region: { code: "1" } }, { region: { code: "1" } }], k, null)).toEqual([[false], [true]]);
  });

  it("always shows a column that has no key (the row's own date)", () => {
    expect(changedCells([{ a: 1 }, { a: 1 }], [undefined, (r: { a: number }) => r.a], null)).toEqual([
      [true, false],
      [true, true],
    ]);
  });
});
