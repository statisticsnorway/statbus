import type { PostgrestClient } from "@supabase/postgrest-js";
import {
  defaultEditRange,
  type EditRange,
  type TimeContextRange,
} from "@/components/form/edit-range";

/**
 * Which rows an edit field shows over time: the table, the row keys that pick
 * this unit's rows (e.g. { id } for a legal unit's name, { legal_unit_id, type }
 * for its physical location), and the column the field edits.
 */
export interface EditFieldSource {
  table: string;
  match: Record<string, string | number>;
  column: string;
}

export interface ReadEditRangeArgs extends EditFieldSource {
  shownValue: unknown;
  context: TimeContextRange;
}

/**
 * Reads the field's rows for the unit and returns the default edit range: the
 * stretch where the shown value is valid, bounded by the selected time context
 * (see defaultEditRange). One standard read, made when the user starts an edit.
 * When the read fails the range is the selected context, so the edit still
 * opens and the database's for-portion-of views clip it to where the unit exists.
 */
export async function readEditRange(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: PostgrestClient<any, any, any>,
  { table, match, column, shownValue, context }: ReadEditRangeArgs
): Promise<EditRange> {
  let query = client.from(table).select(`valid_from,valid_to,${column}`);
  for (const [key, value] of Object.entries(match)) query = query.eq(key, value);
  const { data, error } = await query.order("valid_from");
  if (error || !data) {
    return { validFrom: context.valid_from, validTo: context.valid_to };
  }
  const rows = (data as Record<string, unknown>[]).map((r) => ({
    valid_from: String(r.valid_from),
    valid_to: String(r.valid_to),
    value: r[column],
  }));
  return defaultEditRange(rows, shownValue, context, (a, b) =>
    String(a ?? "") === String(b ?? "")
  );
}
