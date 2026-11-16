/**
 * What a save over ticked periods writes (owner 2026-11-16).
 *
 * A change applies to a stretch of the record's history whose periods may hold
 * different values. Each period keeps its own value for every column the user
 * leaves alone. The form posts what the edit started from (EDIT_START_FIELD:
 * the stretch's values and which columns differ) and which of data source and
 * comment the user set (EDIT_CHOSEN_FIELD); the server derives the kept
 * columns (keptColumns) and leaves them out of the update (updatePayload). A
 * form without EDIT_START_FIELD (a new record, which has no values to keep)
 * writes every field it validated.
 */
export const EDIT_START_FIELD = "edit_start";
export const EDIT_CHOSEN_FIELD = "edit_chosen";

/**
 * The value a field holds while its ticked periods differ and the user has
 * not chosen one: it shows "Differs" and the save keeps each period's own
 * value. Choosing any value, including none, sets that value for the stretch.
 */
export const DIFFERS = "__differs__";

/** A value as the form holds it: the empty string for no value. */
export const asFormValue = (v: unknown) => (v == null ? "" : String(v));

/** What the edit started from over the ticked stretch (editStartValues), as posted. */
export interface EditStart {
  values: Record<string, unknown>;
  /** Columns whose ticked periods hold different values. */
  differing: readonly string[];
}

/** Which of the data source and the comment the user set in this edit. */
export interface EditChosen {
  dataSource: boolean;
  comment: boolean;
}

/**
 * The columns the save keeps: a field whose ticked periods agree when its
 * posted value is still theirs; a field whose periods differ while it still
 * posts DIFFERS; the data source and the comment unless the user set them.
 * Every other posted column is the user's and is written.
 */
export function keptColumns(
  form: FormData,
  start: EditStart,
  chosen: EditChosen
): string[] {
  const kept = Object.keys(start.values).filter((column) => {
    if (!form.has(column)) return true;
    const posted = asFormValue(form.get(column));
    return start.differing.includes(column)
      ? posted === DIFFERS
      : posted === asFormValue(start.values[column]);
  });
  if (!chosen.dataSource) kept.push("data_source_id");
  if (!chosen.comment) kept.push("edit_comment");
  return kept;
}

/** The posted fields for EDIT_START_FIELD and EDIT_CHOSEN_FIELD. */
export function editStartFields(
  start: EditStart,
  chosen: EditChosen
): Record<string, string> {
  return {
    [EDIT_START_FIELD]: JSON.stringify({
      values: start.values,
      differing: start.differing,
    }),
    [EDIT_CHOSEN_FIELD]: [
      chosen.dataSource && "data_source_id",
      chosen.comment && "edit_comment",
    ]
      .filter(Boolean)
      .join(","),
  };
}

/**
 * The posted form to validate and the columns the update keeps. A kept column
 * is validated with the value the edit started from (a field still showing
 * "Differs" posts DIFFERS, which no schema accepts); the update leaves it out.
 */
export function editFormForValidation(formData: FormData): {
  form: FormData;
  kept: string[] | null;
} {
  const raw = formData.get(EDIT_START_FIELD);
  if (raw == null || raw === "") return { form: formData, kept: null };
  const start = JSON.parse(String(raw)) as EditStart;
  const chosenRaw = String(formData.get(EDIT_CHOSEN_FIELD) ?? "");
  const kept = keptColumns(formData, start, {
    dataSource: chosenRaw.includes("data_source_id"),
    comment: chosenRaw.includes("edit_comment"),
  });
  const form = new FormData();
  for (const [key, value] of formData.entries()) form.append(key, value);
  for (const column of kept)
    if (column in start.values)
      form.set(column, asFormValue(start.values[column]));
  return { form, kept };
}

/** The update's payload: the validated fields without the kept columns; the period always stays. */
export function updatePayload<
  T extends { valid_from: unknown; valid_to: unknown } & Record<
    string,
    unknown
  >,
>(validated: T, kept: readonly string[] | null): Partial<T> {
  if (kept == null) return validated;
  const payload: Record<string, unknown> = {};
  for (const [column, value] of Object.entries(validated))
    if (
      column === "valid_from" ||
      column === "valid_to" ||
      !kept.includes(column)
    )
      payload[column] = value;
  return payload as Partial<T>;
}
