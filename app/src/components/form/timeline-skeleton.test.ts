import { skeletonPieces, skeletonSelectionRange } from "@/components/form/timeline-skeleton";
import type { TimeFrame } from "@/lib/time-frame";

// A record a unit does not have yet (a first contact, a first postal address)
// has no timeline of its own. Its Timeline view is a skeleton: the frames cut
// to where the unit exists (the cap), one piece per frame, empty, to be picked.
// Pieces outside the unit's existence are drawn but cannot be picked. The Live
// frame's piece is picked to start with (owner 2026-11-12, STATBUS-609).
const frame = (
  ident: string,
  kind: TimeFrame["kind"],
  valid_from: string,
  valid_to: string,
  equals_frame_ident: string | null = null
) => ({ ident, kind, name: ident, valid_from, valid_to, valid_on: valid_from, year: null, equals_frame_ident }) as TimeFrame;

const frames = [
  frame("live", "live", "2026-01-01", "infinity"),
  frame("prev", "relative", "2025-01-01", "2025-12-31"),
  frame("y_2025", "fixed", "2025-01-01", "2025-12-31", "prev"),
  frame("y_2024", "fixed", "2024-01-01", "2024-12-31"),
  frame("y_2023", "fixed", "2023-01-01", "2023-12-31"),
];

const shape = (pieces: ReturnType<typeof skeletonPieces>) =>
  pieces.map((p) => [p.frame?.ident ?? null, p.valid_from, p.valid_to, p.available]);

describe("skeletonPieces", () => {
  it("cuts the frames to the unit's existence, oldest first, a relative frame once", () => {
    expect(shape(skeletonPieces(frames, [{ validFrom: "2024-03-15", validTo: "infinity" }]))).toEqual([
      ["y_2023", "2023-01-01", "2023-12-31", false],
      ["y_2024", "2024-03-15", "2024-12-31", true],
      ["prev", "2025-01-01", "2025-12-31", true],
      ["live", "2026-01-01", "infinity", true],
    ]);
  });

  it("starts the Live piece where the unit starts when the unit is born inside it", () => {
    expect(shape(skeletonPieces(frames, [{ validFrom: "2026-05-01", validTo: "infinity" }]))).toEqual([
      ["y_2023", "2023-01-01", "2023-12-31", false],
      ["y_2024", "2024-01-01", "2024-12-31", false],
      ["prev", "2025-01-01", "2025-12-31", false],
      ["live", "2026-05-01", "infinity", true],
    ]);
  });

  it("ends the pieces where the unit ends", () => {
    expect(shape(skeletonPieces(frames, [{ validFrom: "2023-01-01", validTo: "2025-06-30" }]))).toEqual([
      ["y_2023", "2023-01-01", "2023-12-31", true],
      ["y_2024", "2024-01-01", "2024-12-31", true],
      ["prev", "2025-01-01", "2025-06-30", true],
      ["live", "2026-01-01", "infinity", false],
    ]);
  });

  it("adds the time before the oldest frame as a piece when the unit existed then", () => {
    expect(shape(skeletonPieces(frames, [{ validFrom: "2020-01-01", validTo: "infinity" }]))[0]).toEqual([
      null,
      "2020-01-01",
      "2022-12-31",
      true,
    ]);
  });
});

describe("skeletonSelectionRange", () => {
  const pieces = skeletonPieces(frames, [{ validFrom: "2024-03-15", validTo: "infinity" }]);

  it("is the picked pieces' stretch", () => {
    expect(skeletonSelectionRange(pieces, [1, 2])).toEqual({ validFrom: "2024-03-15", validTo: "2025-12-31" });
    expect(skeletonSelectionRange(pieces, [3])).toEqual({ validFrom: "2026-01-01", validTo: "infinity" });
  });

  it("is nothing when nothing is picked", () => {
    expect(skeletonSelectionRange(pieces, [])).toBeNull();
  });
});
