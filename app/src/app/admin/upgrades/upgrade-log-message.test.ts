/**
 * Tests for the upgrade-log fetch failure wording (STATBUS-456 A3).
 *
 * A 404 means the log is genuinely not in this copy of the database (dump
 * restored elsewhere without its companion archive) — a plain statement,
 * not a red error. Any other failure keeps its real message.
 */
import { upgradeLogFetchFailureText } from "./upgrade-log-message";

describe("upgradeLogFetchFailureText", () => {
  test("HTTP 404 renders a plain not-available statement, not an error box", () => {
    const text = upgradeLogFetchFailureText(404, "HTTP 404");
    expect(text).toBe(
      "This log is not available in this copy of the database."
    );
    expect(text).not.toContain("Failed to load log");
  });

  test("a non-404 HTTP failure keeps its real error message", () => {
    expect(upgradeLogFetchFailureText(500, "HTTP 500")).toBe(
      "Failed to load log: HTTP 500"
    );
    expect(upgradeLogFetchFailureText(403, "HTTP 403")).toBe(
      "Failed to load log: HTTP 403"
    );
  });

  test("a network failure (no status) keeps its real error message", () => {
    expect(upgradeLogFetchFailureText(null, "fetch failed")).toBe(
      "Failed to load log: fetch failed"
    );
  });
});
