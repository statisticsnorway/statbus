import { dateOutsideBounds } from "@/components/time-frame-panel";

// A date typed into Advanced's From/To is checked against where the unit exists
// (the bounds an edit of a unit's record passes): outside, the field says so and
// the save is held. Imports and a unit's own fields pass no bounds.
describe("dateOutsideBounds", () => {
  const bounds = { from: "2023-01-01", to: "infinity" };

  it("names the unit's first day for a date before it", () => {
    expect(dateOutsideBounds("2022-01-01", bounds)).toBe("The unit exists from 2023-01-01");
  });

  it("names the unit's last day for a date after it", () => {
    expect(dateOutsideBounds("2026-01-01", { from: "2020-01-01", to: "2025-06-30" })).toBe(
      "The unit exists until 2025-06-30"
    );
  });

  it("accepts a date inside, an open end, an unfinished date, and any date without bounds", () => {
    expect(dateOutsideBounds("2023-01-01", bounds)).toBeNull();
    expect(dateOutsideBounds("infinity", bounds)).toBeNull();
    expect(dateOutsideBounds("2022-0", bounds)).toBeNull();
    expect(dateOutsideBounds("1999-01-01", undefined)).toBeNull();
  });
});
