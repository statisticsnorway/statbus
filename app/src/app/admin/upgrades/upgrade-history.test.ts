import { historyRowsForPill, partitionUpgradeRows } from "./upgrade-history";

const row = (id: number, state: string) => ({ id, state });

test("the running row is excluded from every bucket", () => {
  const rows = [
    row(1, "completed"),
    row(2, "superseded"),
    row(3, "available"),
    row(4, "in_progress"),
    row(5, "failed"),
    row(6, "completed"),
  ];
  const { history, available, actionable } = partitionUpgradeRows(rows, 6);
  expect(history.map((r) => r.id)).toEqual([1, 2]);
  expect(available.map((r) => r.id)).toEqual([3]);
  expect(actionable.map((r) => r.id)).toEqual([4, 5]);
  // The running row appears once, in the Running card — nowhere else.
  expect(
    [...history, ...available, ...actionable].some((r) => r.id === 6)
  ).toBe(false);
});

test("partition keeps everything when no running row is identified", () => {
  const rows = [row(1, "completed"), row(2, "available")];
  const { history, available, actionable } = partitionUpgradeRows(rows, null);
  expect(history).toHaveLength(1);
  expect(available).toHaveLength(1);
  expect(actionable).toHaveLength(0);
});

test("applied pill means completed only — never skipped or dismissed", () => {
  const rows = [
    row(1, "completed"),
    row(2, "skipped"),
    row(3, "dismissed"),
    row(4, "superseded"),
  ];
  expect(historyRowsForPill(rows, "applied").map((r) => r.id)).toEqual([1]);
});

test("skipped pill groups skipped and dismissed", () => {
  const rows = [
    row(1, "completed"),
    row(2, "skipped"),
    row(3, "dismissed"),
    row(4, "superseded"),
  ];
  expect(historyRowsForPill(rows, "skipped").map((r) => r.id)).toEqual([2, 3]);
  expect(historyRowsForPill(rows, "superseded").map((r) => r.id)).toEqual([4]);
});
