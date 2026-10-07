/**
 * Observability for search exports (STATBUS-421).
 *
 * The old `/api/search/export` route swallowed mid-stream failures
 * (`controller.error` with no logging), which is why a dead export was
 * invisible in log.statbus.org. With the browser calling `/rest` directly,
 * the client is the only place that knows the export failed mid-stream — so
 * failures (and completions of large exports, for timing measurement) are
 * reported to `/api/logger`, which forwards them to the server log with the
 * user's session context.
 */

export interface ExportLogContext {
  format: "csv" | "xlsx";
  /** Full PostgREST request URL (path + query), the export's definition. */
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
