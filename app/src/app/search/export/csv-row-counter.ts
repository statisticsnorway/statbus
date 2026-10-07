/**
 * Incremental CSV record counter for export progress (STATBUS-421).
 *
 * Counts records (newlines outside quoted fields) over a byte stream, so the
 * UI can show "rows received of N" while a text/csv response streams in.
 * Quote state carries across chunk boundaries, and `""` escape sequences are
 * handled (they toggle the quote state twice, ending where they started).
 */

const DOUBLE_QUOTE = 0x22; // "
const LINE_FEED = 0x0a; // \n

export interface CsvRowCounter {
  /** Feed the next chunk of response bytes. */
  push(chunk: Uint8Array): void;
  /** Newlines seen outside quoted fields so far (includes the header line). */
  readonly lines: number;
  /** Data records seen so far (lines minus the header line, floored at 0). */
  readonly records: number;
}

export function createCsvRowCounter(): CsvRowCounter {
  let inQuotes = false;
  let lines = 0;
  // PostgREST does not terminate the last record with a newline, so a line
  // with content but no trailing \n still counts.
  let hasDataOnCurrentLine = false;
  return {
    push(chunk: Uint8Array) {
      for (let i = 0; i < chunk.length; i++) {
        const byte = chunk[i];
        if (byte === DOUBLE_QUOTE) {
          inQuotes = !inQuotes;
          hasDataOnCurrentLine = true;
        } else if (byte === LINE_FEED && !inQuotes) {
          lines++;
          hasDataOnCurrentLine = false;
        } else {
          hasDataOnCurrentLine = true;
        }
      }
    },
    get lines() {
      return lines + (hasDataOnCurrentLine ? 1 : 0);
    },
    get records() {
      return Math.max(0, this.lines - 1);
    },
  };
}
