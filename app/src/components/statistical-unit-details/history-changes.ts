/**
 * Which cells of a unit's history table changed from the version before.
 *
 * Each history row is a stretch of time in which the unit's values hold; a
 * new version starts when any value changes, so most cells repeat the older
 * version. The table lists versions newest first, shows the changed cells and
 * dims the repeats, making a unit with many changes readable (owner
 * 2026-11-13). A row compares with the row below it; the last row compares
 * with `nextOlder`, the version just older than the rows shown, so dimming
 * holds across page boundaries (cgtb4y). The unit's oldest version has none
 * (null), so all its cells count as changed. A column's key gives the value
 * it compares; a column without one (the row's own date) always shows.
 */
export function changedCells<Row>(
  rows: readonly Row[],
  keys: readonly (((row: Row) => unknown) | undefined)[],
  nextOlder: Row | null
): boolean[][] {
  return rows.map((row, i) => {
    const older = i + 1 < rows.length ? rows[i + 1] : nextOlder;
    return keys.map((key) => older === null || !key || !sameValue(key(row), key(older)));
  });
}

const sameValue = (a: unknown, b: unknown) =>
  JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
