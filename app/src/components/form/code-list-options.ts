/** One entry in an edit form's select. */
export interface CodeListOption {
  value: number | string;
  label: string;
  disabled: boolean;
  /** The titles of the uncoded ancestors in a tree-shaped code list, joined by ›. */
  group?: string;
}

/** A code list row. `path` (ltree, e.g. DOMESTIC.A.1110) places it in a tree. */
export interface CodeListRow {
  id: number | null;
  code: string | null;
  name: string | null;
  path?: string | null;
}

/**
 * A code list (sector, legal form, region, unit size) as a select's options.
 *
 * A code list may be a tree, given by `path`. Its rows without a code (sector
 * "Domestic sectors" › "Non-financial corporations") are the inner nodes that
 * name a group: a unit is classified by a coded row, which is also what an
 * import names, so the uncoded rows are not options but the group titles of
 * the coded rows under them. Coded rows keep path order; a coded inner node
 * (region "Europe" above "Denmark") stays a choice.
 *
 * An optional field's list starts with None, whose empty value stores no
 * value (STATBUS-610), the same as an empty cell in an import.
 */
export function codeListOptions(
  rows: readonly CodeListRow[],
  {
    optional = false,
    showCode = true,
  }: { optional?: boolean; showCode?: boolean } = {}
): CodeListOption[] {
  const ordered = rows.some((row) => row.path)
    ? [...rows].sort((a, b) => comparePaths(a.path ?? "", b.path ?? ""))
    : rows;
  const titleOf = new Map(
    rows
      .filter((row) => row.path && !row.code)
      .map((row) => [row.path!, `${row.name}`])
  );
  const options = ordered
    .filter((row) => !showCode || row.code)
    .map((row) => {
      const group = groupTitle(row.path, titleOf);
      return {
        value: row.id!,
        label: showCode ? `${row.code} ${row.name}` : `${row.name}`,
        disabled: false,
        ...(group ? { group } : {}),
      };
    });
  return optional
    ? [{ value: "", label: "None", disabled: false }, ...options]
    : options;
}

/**
 * Consecutive options that share a group title, in list order: a select draws
 * each run as one group under its title.
 */
export function groupRuns<T extends { group?: string }>(
  options: readonly T[]
): { title?: string; options: T[] }[] {
  const runs: { title?: string; options: T[] }[] = [];
  for (const option of options) {
    const last = runs[runs.length - 1];
    if (last && last.title === option.group) last.options.push(option);
    else runs.push({ title: option.group, options: [option] });
  }
  return runs;
}

/** The titles of a path's uncoded ancestors, root first. */
function groupTitle(
  path: string | null | undefined,
  titleOf: Map<string, string>
): string | undefined {
  if (!path) return undefined;
  const labels = path.split(".");
  const titles = labels
    .slice(0, -1)
    .map((_, i) => titleOf.get(labels.slice(0, i + 1).join(".")))
    .filter((title): title is string => title !== undefined);
  return titles.length ? titles.join(" › ") : undefined;
}

/** ltree order: label by label, numeric labels by value. */
function comparePaths(a: string, b: string): number {
  const as = a.split(".");
  const bs = b.split(".");
  for (let i = 0; i < Math.min(as.length, bs.length); i++) {
    if (as[i] !== bs[i])
      return as[i].localeCompare(bs[i], undefined, { numeric: true });
  }
  return as.length - bs.length;
}
