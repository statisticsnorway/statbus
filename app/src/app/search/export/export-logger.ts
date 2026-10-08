/**
 * Observability for search exports (STATBUS-421).
 *
 * The export route (`/api/search/export`) logs its own failures with rows
 * sent, expected rows, bytes and elapsed time. Some failures are only
 * visible in the browser (a short stream, a disk-write failure, an Excel
 * refusal, a cancelled save), so the client additionally reports failures
 * (and completions of large exports, for timing measurement) to
 * `/api/logger`, which forwards them to the server log with the user's
 * session context.
 */

export interface ExportLogContext {
  format: "csv" | "xlsx";
  /** The export request URL (path + query), the export's definition. */
  url: string;
  rowsReceived: number;
  expectedRows: number | null;
  bytesReceived: number;
  elapsedMs: number;
  error?: string;
}

/**
 * Fire-and-forget report to the server log. Never throws: logging must not
 * mask the export outcome itself.
 */
export async function reportExportEvent(
  level: "info" | "error",
  message: string,
  context: ExportLogContext
): Promise<void> {
  try {
    await fetch("/api/logger", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        level,
        event: { messages: [{ ...context }, message] },
        location: typeof window !== "undefined" ? window.location : null,
      }),
    });
  } catch (loggingError) {
    console.error(
      "Failed to report export event to /api/logger:",
      loggingError
    );
  }
}
