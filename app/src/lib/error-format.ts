/**
 * describeError — render an unknown error to a human-readable string
 * suitable for the UI.
 *
 * Why: catch sites that did `err instanceof Error ? err.message :
 * String(err)` collapse PostgREST/supabase errors (which are plain
 * objects shaped `{ message, details, hint, code }`, NOT Error
 * instances) to the literal `"[object Object]"` — useless to operators.
 *
 * This helper handles:
 *   - JavaScript Error instances
 *   - PostgREST/supabase PostgrestError-shaped objects
 *   - Anything else with a string `.message` property (axios, fetch
 *     wrappers, etc.)
 *   - Falls back to JSON.stringify, then String() if even that fails
 */
type PostgrestErrorShape = {
  message: string;
  details?: string;
  hint?: string;
  code?: string;
};

function isPostgrestErrorShape(x: unknown): x is PostgrestErrorShape {
  return (
    typeof x === "object" &&
    x !== null &&
    "message" in x &&
    typeof (x as { message: unknown }).message === "string"
  );
}

export function describeError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (isPostgrestErrorShape(err)) {
    const e = err;
    const parts = [e.message, e.details, e.hint, e.code && `(code: ${e.code})`]
      .filter((p): p is string => typeof p === "string" && p.length > 0);
    return parts.join(" — ");
  }
  if (err && typeof err === "object") {
    try {
      return JSON.stringify(err);
    } catch {
      return Object.prototype.toString.call(err);
    }
  }
  return String(err);
}
