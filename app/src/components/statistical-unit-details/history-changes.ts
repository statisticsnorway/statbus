/**
 * Which cells of a unit's history table changed from the row above.
 *
 * Each history row is a stretch of time in which the unit's values hold; a
 * new row starts when any value changes, so most cells repeat the row above.
 * The table shows the changed cells and dims the repeats, making a unit with
 * many changes readable. A column's key gives the value it compares; a column
 * without one (the row's own date) always shows. The first row has no row
 * above, so all its cells count as changed.
 */
export function changedCells<Row>(
  rows: readonly Row[],
  keys: readonly (((row: Row) => unknown) | undefined)[]
): boolean[][] {
  return rows.map((row, i) =>
    keys.map((key) => i === 0 || !key || !sameValue(key(row), key(rows[i - 1])))
  );
}

const sameValue = (a: unknown, b: unknown) =>
  JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
