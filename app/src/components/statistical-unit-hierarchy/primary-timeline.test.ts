/**
 * 2f4c0z: the Set as primary dialog's Timeline view shows who is primary when, one period per stretch
 * with the same primary, so the user ticks the stretches to change.
 */
import { primaryTimeline } from "./primary-timeline";

const row = (id: number, name: string, from: string, to: string, primary: boolean) => ({
  id,
  name,
  valid_from: from,
  valid_to: to,
  primary,
});

describe("who is primary when", () => {
  it("is one period while the primary does not change", () => {
    const periods = primaryTimeline([
      row(1, "A", "2020-01-01", "infinity", true),
      row(2, "B", "2020-01-01", "infinity", false),
    ]);
    expect(periods.map((p) => [p.valid_from, p.valid_to, p.values.primary])).toEqual([
      ["2020-01-01", "infinity", "A"],
    ]);
  });

  it("splits where the primary changes, and joins rows split for other reasons", () => {
    const periods = primaryTimeline([
      row(1, "A", "2020-01-01", "2022-12-31", true),
      row(1, "A", "2023-01-01", "2023-12-31", true),
      row(1, "A", "2024-01-01", "infinity", false),
      row(2, "B", "2020-01-01", "2023-12-31", false),
      row(2, "B", "2024-01-01", "infinity", true),
    ]);
    expect(periods.map((p) => [p.valid_from, p.valid_to, p.values.primary])).toEqual([
      ["2020-01-01", "2023-12-31", "A"],
      ["2024-01-01", "infinity", "B"],
    ]);
  });

  it("shows a stretch with no primary as its own period", () => {
    const periods = primaryTimeline([
      row(1, "A", "2020-01-01", "2021-12-31", false),
      row(1, "A", "2022-01-01", "infinity", true),
    ]);
    expect(periods.map((p) => [p.valid_from, p.valid_to, p.values.primary])).toEqual([
      ["2020-01-01", "2021-12-31", null],
      ["2022-01-01", "infinity", "A"],
    ]);
  });
});
