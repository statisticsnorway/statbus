/**
 * What a Download menu says (f69jcx): the rows it downloads, stated once above its formats, whether
 * Excel can hold them, and the notification when a download is done. Shared by the search, a unit's
 * history and an import job's data, so every Download reads the same.
 */
import { EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";

/** A count with a space between thousands, as the search total shows it (1 134 475). */
export function formatRowCount(n: number): string {
  return n.toLocaleString("en-US").replace(/,/g, " ");
}

/** The menu's heading: how many rows a download holds, or null when the count is not known. */
export function downloadMenuHeading(rows: number | null | undefined): string | null {
  if (rows == null) return null;
  return `${formatRowCount(rows)} ${rows === 1 ? "row" : "rows"}`;
}

/** Why Excel is not offered, or null when the rows fit in one sheet (EXCEL_MAX_DATA_ROWS). */
export function excelUnavailableReason(rows: number | null | undefined): string | null {
  if (rows == null || rows <= EXCEL_MAX_DATA_ROWS) return null;
  return `Excel holds at most ${formatRowCount(EXCEL_MAX_DATA_ROWS)} rows. Use CSV.`;
}

function formatElapsed(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

/** The notification a finished download shows: what was saved and how long it took. */
export function downloadedMessage(
  what: { rows: number } | { bytes: number },
  elapsedMs: number
): string {
  const amount =
    "rows" in what
      ? `${formatRowCount(what.rows)} ${what.rows === 1 ? "row" : "rows"}`
      : formatBytes(what.bytes);
  return `Downloaded ${amount} in ${formatElapsed(elapsedMs)}`;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
