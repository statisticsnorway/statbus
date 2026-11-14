import type { PostgrestClient } from "@supabase/postgrest-js";
import {
  defaultEditRange,
  type EditRange,
  type TimeFrameRange,
} from "@/components/form/edit-range";

/**
 * Which rows an edit field shows over time: the table, the row keys that pick
 * this unit's rows (e.g. { id } for a legal unit's name, { legal_unit_id, type }
 * for its physical location), and the column or columns the field edits. A field
 * group (an address, contact details) names all its columns; its shown value is
 * then those columns' values together.
 */
export interface EditFieldSource {
  table: string;
  match: Record<string, string | number>;
  column: string | string[];
}

/**
 * The edit's default period (defaultEditRange) and where its value came from:
 * the data source and comment of the row holding the shown value on the
 * period's first day. The edit starts with them, so a save that changes neither
 * keeps them; the user can change or clear either. Absent when the rows could
 * not be read.
 */
export interface EditStart extends EditRange {
  dataSourceId?: string | null;
  editComment?: string | null;
}

export interface ReadEditRangeArgs extends EditFieldSource {
  shownValue: unknown;
  context: TimeFrameRange;
}

/** The columns a location field group shows and edits together. */
export const LOCATION_COLUMNS = [
  "address_part1",
  "address_part2",
  "address_part3",
  "postcode",
  "postplace",
  "region_id",
  "country_id",
  "physical_latitude",
  "physical_longitude",
  "altitude",
] as const;

/**
 * Reads the field's rows for the unit and returns the default edit range: the
 * stretch where the shown value is valid, bounded by the selected time frame
 * (see defaultEditRange). One standard read, made when the user starts an edit.
 * When the read fails the range is the selected context, so the edit still
 * opens and the database's for-portion-of views clip it to where the unit exists.
 */
export async function readEditRange(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: PostgrestClient<any, any, any>,
  { table, match, column, shownValue, context }: ReadEditRangeArgs
): Promise<EditStart> {
  const columns = Array.isArray(column) ? column : [column];
  let query = client
    .from(table)
    .select(`valid_from,valid_to,data_source_id,edit_comment,${columns.join(",")}`);
  for (const [key, value] of Object.entries(match)) query = query.eq(key, value);
  const { data, error } = await query.order("valid_from");
  if (error || !data) {
    return { validFrom: context.valid_from, validTo: context.valid_to };
  }
  const valueOf = (r: Record<string, unknown>) =>
    columns.map((c) => String(r[c] ?? "")).join("\u0000");
  const rows = (data as unknown as Record<string, unknown>[]).map((r) => ({
    valid_from: String(r.valid_from),
    valid_to: String(r.valid_to),
    value: valueOf(r),
  }));
  const shown = Array.isArray(column)
    ? valueOf((shownValue ?? {}) as Record<string, unknown>)
    : String(shownValue ?? "");
  const range = defaultEditRange(rows, shown, context);
  const first = (data as unknown as Record<string, unknown>[]).find(
    (r) => String(r.valid_from) <= range.validFrom && (r.valid_to === "infinity" || String(r.valid_to) >= range.validFrom)
  );
  return {
    ...range,
    dataSourceId: first?.data_source_id == null ? null : String(first.data_source_id),
    editComment: first?.edit_comment ? String(first.edit_comment) : null,
  };
}
