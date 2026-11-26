/**
 * 2f4c0z: Set as primary applies to a stretch of time: the live frame unless the user picks another
 * frame or Specific dates, passed to the database as valid_from and an inclusive valid_to.
 */
import { liveFrame, primaryChangePeriod } from "./primary-change-period";

const live = { kind: "live" as const, valid_from: "2026-01-01", valid_to: "infinity" };
const prev = { kind: "relative" as const, valid_from: "2025-01-01", valid_to: "2025-12-31" };

describe("the period of a Set as primary", () => {
  it("is the chosen frame's period", () => {
    expect(primaryChangePeriod("frame", live, null, null)).toEqual({ validFrom: "2026-01-01", validTo: "infinity" });
    expect(primaryChangePeriod("frame", prev, null, null)).toEqual({ validFrom: "2025-01-01", validTo: "2025-12-31" });
  });

  it("is the user's dates, open-ended when To is empty", () => {
    expect(primaryChangePeriod("dates", live, "2024-03-01", "2024-12-31")).toEqual({
      validFrom: "2024-03-01",
      validTo: "2024-12-31",
    });
    expect(primaryChangePeriod("dates", live, "2024-03-01", null)).toEqual({ validFrom: "2024-03-01", validTo: "infinity" });
  });

  it("is incomplete without a frame or a From date", () => {
    expect(primaryChangePeriod("frame", null, null, null)).toBeNull();
    expect(primaryChangePeriod("dates", live, null, "2024-12-31")).toBeNull();
  });
});

describe("the frame a Set as primary starts on", () => {
  it("is the live frame", () => {
    expect(liveFrame([prev, live])).toBe(live);
  });
});
