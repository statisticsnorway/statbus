import { addMeasure, MAX_MEASURES } from "./measure-picker";

// ppvxg2, owner 2026-11-27 22:47: installations can have seven or eight variables, so at most three
// measures show at once, the primary included; checking another drops the earliest added (FIFO).
describe("addMeasure", () => {
  it("keeps the primary and the two most recently added, dropping the earliest added", () => {
    let shown = ["units"];
    shown = addMeasure(shown, "units", "employees");
    shown = addMeasure(shown, "units", "turnover");
    const atCap = shown;
    shown = addMeasure(shown, "units", "assets");
    expect({ atCap, afterFourth: shown, max: MAX_MEASURES }).toEqual({
      atCap: ["units", "employees", "turnover"],
      afterFourth: ["units", "turnover", "assets"],
      max: 3,
    });
  });

  it("keeps a primary that is a variable first, whatever was added", () => {
    expect(addMeasure(["employees", "units"], "employees", "turnover")).toEqual(["employees", "units", "turnover"]);
  });
});
