/** One entry in an edit form's select. */
export interface CodeListOption {
  value: number | string;
  label: string;
  disabled: boolean;
}

/**
 * A code list (sector, legal form, region, unit size) as a select's options.
 *
 * A row is labelled by its code and name. A row without a code is a heading in
 * the list's hierarchy (e.g. sector "Domestic sectors" above the coded
 * sectors): the import can't name it either, as it looks rows up by code, so
 * it is shown but can't be chosen.
 *
 * An optional field's list starts with None, whose empty value stores no
 * value (STATBUS-610), the same as an empty cell in an import.
 */
export function codeListOptions(
  rows: readonly { id: number | null; code: string | null; name: string | null }[],
  { optional = false, showCode = true }: { optional?: boolean; showCode?: boolean } = {}
): CodeListOption[] {
  const options = rows.map((row) => ({
    value: row.id!,
    label: showCode && row.code ? `${row.code} ${row.name}` : `${row.name}`,
    disabled: showCode && !row.code,
  }));
  return optional ? [{ value: "", label: "None", disabled: false }, ...options] : options;
}
