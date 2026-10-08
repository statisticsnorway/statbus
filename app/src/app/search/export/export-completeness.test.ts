import {
  exportIncompleteError,
  parseContentRangeTotal,
  resolveExpectedRows,
} from "./export-completeness";

describe("parseContentRangeTotal", () => {
  it("reads the exact total PostgREST announces", () => {
    expect(parseContentRangeTotal("0-1976462/1976463")).toBe(1_976_463);
  });

  it("reads an empty result's total", () => {
    expect(parseContentRangeTotal("*/0")).toBe(0);
  });

  it("returns null when the total is unknown or the header is absent", () => {
    expect(parseContentRangeTotal("0-1976462/*")).toBeNull();
    expect(parseContentRangeTotal(null)).toBeNull();
    expect(parseContentRangeTotal("")).toBeNull();
    expect(parseContentRangeTotal("garbage")).toBeNull();
  });
});

describe("resolveExpectedRows", () => {
  it("prefers the server's exact total over the search page's total", () => {
    // The search page showed an estimate; the server counted the response.
    expect(resolveExpectedRows("0-1976462/1976463", 1_900_000, false)).toEqual({
      rows: 1_976_463,
      source: "content-range",
    });
    // Even an exact search total yields to the count of this very response.
    expect(resolveExpectedRows("0-1976462/1976463", 1_976_000, true)).toEqual({
      rows: 1_976_463,
      source: "content-range",
    });
  });

  it("falls back to an exact search total when the header has no total", () => {
    expect(resolveExpectedRows("0-1976462/*", 1_976_463, true)).toEqual({
      rows: 1_976_463,
      source: "search-total",
    });
    expect(resolveExpectedRows(null, 1_976_463, true)).toEqual({
      rows: 1_976_463,
      source: "search-total",
    });
  });

  it("does not judge completeness by a planner estimate", () => {
    expect(resolveExpectedRows(null, 1_900_000, false)).toBeNull();
    expect(resolveExpectedRows(null, null, true)).toBeNull();
  });
});

describe("exportIncompleteError", () => {
  it("accepts an export that received every announced row", () => {
    expect(
      exportIncompleteError(
        1_976_463,
        resolveExpectedRows("0-1976462/1976463", null, false)
      )
    ).toBeNull();
  });

  it("errors on the historical shortfall, naming both counts", () => {
    // 1,976,463 - 29,470: the rows the arrow projection silently dropped.
    const error = exportIncompleteError(
      1_946_993,
      resolveExpectedRows("0-1976462/1976463", 1_946_993, true)
    );
    expect(error).toContain("received 1 946 993 rows");
    expect(error).toContain("expected 1 976 463");
    expect(error).toContain("exact count reported by the server");
    expect(error).toContain("not saved");
  });

  it("errors against the exact search total when no server total exists", () => {
    const error = exportIncompleteError(
      100_000,
      resolveExpectedRows(null, 1_976_463, true)
    );
    expect(error).toContain("received 100 000 rows");
    expect(error).toContain("expected 1 976 463 (the search total)");
  });

  it("cannot check without a trustworthy total", () => {
    expect(exportIncompleteError(5, null)).toBeNull();
  });
});
