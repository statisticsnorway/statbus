/**
 * Display text for a failed upgrade-log fetch (STATBUS-456 A3).
 *
 * An HTTP 404 means the log file is genuinely not in this copy of the
 * database (the dump was taken elsewhere and the companion archive is
 * absent) — that is a fact about the data, not an error, so it renders as a
 * plain statement rather than a red "Failed to load log" box. Any other
 * failure (network, 5xx, ...) keeps its real error message.
 */
export function upgradeLogFetchFailureText(
  status: number | null,
  message: string
): string {
  if (status === 404) {
    return "This log is not available in this copy of the database.";
  }
  return `Failed to load log: ${message}`;
}
