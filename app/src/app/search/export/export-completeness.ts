/**
 * Export completeness guard (STATBUS-421).
 *
 * An export is only saved when the rows received match the number of rows
 * the export was supposed to contain. The strongest evidence of that number
 * is the EXACT total PostgREST announces in the `Content-Range` response
 * header (`0-1976462/1976463`) when the request sends `Prefer: count=exact`:
 * it is counted by the same statement that produces the rows, so it describes
 * exactly this response. The search page's total is only a fallback, because
 * it may be a planner estimate and was counted by an earlier request.
 */

/** The request header that makes PostgREST announce the exact total. */
export const EXACT_COUNT_PREFER = "count=exact";

/**
 * The total (denominator) from a PostgREST `Content-Range` header, e.g.
 * `0-1976462/1976463` -> 1976463 and `*\/0` -> 0. Returns null when the
 * header is absent or the total is unknown (`0-24/*`).
 */
export function parseContentRangeTotal(
  contentRange: string | null | undefined
): number | null {
  if (!contentRange) return null;
  const match = /\/\s*(\d+)\s*$/.exec(contentRange);
  if (!match) return null;
  const total = Number(match[1]);
  return Number.isSafeInteger(total) ? total : null;
}

export type ExpectedRowsSource = "content-range" | "search-total";

export interface ExpectedRows {
  rows: number;
  source: ExpectedRowsSource;
}

/**
 * The total to check the received rows against: the server-announced exact
 * total when present, otherwise the search page's total if it is exact,
 * otherwise null (no trustworthy total, so no check is possible).
 */
export function resolveExpectedRows(
  contentRange: string | null | undefined,
  searchTotal: number | null,
  searchTotalIsExact: boolean
): ExpectedRows | null {
  const serverTotal = parseContentRangeTotal(contentRange);
  if (serverTotal != null) {
    return { rows: serverTotal, source: "content-range" };
  }
  if (searchTotalIsExact && searchTotal != null) {
    return { rows: searchTotal, source: "search-total" };
  }
  return null;
}

function formatCount(n: number): string {
  return n.toLocaleString("en-US").replace(/,/g, " ");
}

/**
 * Null when the export is complete (or no trustworthy total exists), else
 * the user-facing error naming both the received and the expected counts.
 */
export function exportIncompleteError(
  rowsReceived: number,
  expected: ExpectedRows | null
): string | null {
  if (expected == null || rowsReceived === expected.rows) return null;
  const source =
    expected.source === "content-range"
      ? "the exact count reported by the server"
      : "the search total";
  return `Export incomplete: received ${formatCount(rowsReceived)} rows, expected ${formatCount(expected.rows)} (${source}). The download was not saved. Please try again.`;
}
