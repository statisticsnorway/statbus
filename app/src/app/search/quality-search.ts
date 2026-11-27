import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";
import type { QualityCheckRef, QualityRule } from "@/lib/quality-checks";

/**
 * The API parameter a quality search carries until it is resolved: the check as written in the URL
 * (quality=<rule>[:<stat code>]). resolveSearchResource (search-requests.ts) turns it into the
 * PostgREST path and parameters by qualitySearchResource; it is never sent to PostgREST.
 */
export const QUALITY_CHECK_PARAM = "quality_check";

/**
 * Below this many units at the time frame a check's list is read from its store first; from it on,
 * statistical_unit is walked in the page's order. Owner decision 2026-11-26 (05pe0x), kept by h9mhxe.
 * Measured on the Norway copy for a first page sorted by name: filtering first is reliable for a rare
 * check (0.07 ms for 2 units), while the planner cannot see a rare element of quality_check_ids and
 * walks the name index (28 s for a 2-unit check); walking the units is 1.5-19 ms for checks of 21 368
 * and 161 571 units.
 */
export const QUALITY_FINDINGS_FIRST_BELOW = 1000;

/** Where a quality search reads its rows: a PostgREST path and its query parameters. */
export interface QualitySearchResource {
  readonly path: "statistical_unit" | "rpc/statistical_unit_quality";
  readonly params: URLSearchParams;
}

/** The table holding a relation check's findings (public.quality_check kind relation). */
const RELATION_TABLE: Partial<Record<QualityRule, string>> = {
  establishment_activity_differs: "quality_establishment_activity_differs",
  establishments_above_legal_unit: "quality_legal_unit_establishment_stat",
  legal_unit_above_establishments: "quality_legal_unit_establishment_stat",
};

/**
 * The resource for a search that lists the units of one check. `params` are the search's own
 * parameters for statistical_unit (filters, existence at the time frame, order, paging); `units` is
 * the check's count at the time frame (public.quality_check_count, the dashboard's count).
 *
 * Few units: rpc/statistical_unit_quality(quality_check_id, valid_on), which starts from the check's
 * store at the instant; the instant replaces the existence filter, as PostgREST applies
 * computed-field filters only to a table. Many units: statistical_unit in the page's order, a row
 * check filtered by quality_check_ids=cs.{id} (GIN, gin__int_ops), a relation check with its table as
 * an inner embed; it stops at the page. Every path returns the same rows (test/sql/411).
 */
export function qualitySearchResource(
  params: URLSearchParams,
  check: QualityCheckRef,
  units: number
): QualitySearchResource {
  const next = new URLSearchParams(params);
  if (units < QUALITY_FINDINGS_FIRST_BELOW) {
    const validOn = /^lte\.(.+)$/.exec(next.get(EXISTENCE_FROM) ?? "")?.[1];
    if (!validOn) throw new Error("A quality search needs the time frame's existence filter");
    next.delete(EXISTENCE_FROM);
    next.delete(EXISTENCE_UNTIL);
    next.set("quality_check_id", String(check.id));
    next.set("valid_on", validOn);
    return { path: "rpc/statistical_unit_quality", params: next };
  }
  if (check.kind === "row") {
    next.set("quality_check_ids", `cs.{${check.id}}`);
    return { path: "statistical_unit", params: next };
  }
  const table = RELATION_TABLE[check.rule];
  if (!table) throw new Error(`No relation table for the check ${check.rule}`);
  next.set("select", `*,${table}!inner()`);
  next.set(`${table}.check_id`, `eq.${check.id}`);
  return { path: "statistical_unit", params: next };
}
