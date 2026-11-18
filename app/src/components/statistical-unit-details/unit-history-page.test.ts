import { HISTORY_PAGE_SIZE, fetchUnitHistoryPage } from "./unit-history-page";

// A unit's history is read a page at a time, newest first (cgtb4y): the
// request asks the database for one page plus the next older version, which
// the table only compares with, and for the exact count of versions.
function clientRecording(rows: unknown[], count: number) {
  const calls: Record<string, unknown[]> = {};
  const builder = {
    select: (...a: unknown[]) => ((calls.select = a), builder),
    eq: (...a: unknown[]) => ((calls.eq = [...(calls.eq ?? []), a]), builder),
    order: (...a: unknown[]) => ((calls.order = a), builder),
    range: (...a: unknown[]) => ((calls.range = a), builder),
    returns: () => Promise.resolve({ data: rows, count, error: null }),
  };
  return { client: { from: (t: string) => ((calls.from = [t]), builder) }, calls };
}

const version = (valid_from: string) => ({ valid_from });

describe("fetchUnitHistoryPage", () => {
  it("reads the newest page plus one older version, with the exact count", async () => {
    const rows = Array.from({ length: HISTORY_PAGE_SIZE + 1 }, (_, i) => version(`${2100 - i}-01-01`));
    const { client, calls } = clientRecording(rows, 312);
    const page = await fetchUnitHistoryPage(client as never, 28, "legal_unit", 0);

    expect(calls.from).toEqual(["statistical_unit"]);
    expect(calls.eq).toEqual([["unit_id", 28], ["unit_type", "legal_unit"]]);
    expect(calls.order).toEqual(["valid_from", { ascending: false }]);
    expect(calls.range).toEqual([0, HISTORY_PAGE_SIZE]);
    expect(calls.select?.[1]).toEqual({ count: "exact" });
    expect(page.versions).toEqual(rows.slice(0, HISTORY_PAGE_SIZE));
    expect(page.nextOlder).toEqual(rows[HISTORY_PAGE_SIZE]);
    expect(page.total).toBe(312);
    expect(page.error).toBeNull();
  });

  it("reads the next page from where the shown versions end", async () => {
    const { client, calls } = clientRecording([], 312);
    await fetchUnitHistoryPage(client as never, 28, "legal_unit", 100);
    expect(calls.range).toEqual([100, 100 + HISTORY_PAGE_SIZE]);
  });

  it("has no older version after the unit's oldest", async () => {
    const rows = [version("2025-01-01"), version("2024-01-01")];
    const { client } = clientRecording(rows, 2);
    const page = await fetchUnitHistoryPage(client as never, 5, "establishment", 0);
    expect(page.versions).toEqual(rows);
    expect(page.nextOlder).toBeNull();
    expect(page.total).toBe(2);
  });
});
