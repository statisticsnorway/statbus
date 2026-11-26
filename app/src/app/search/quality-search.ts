import { EXISTENCE_FROM, EXISTENCE_UNTIL } from "@/lib/unit-existence";
import type { QualityCheckRef } from "@/lib/quality-checks";

/**
 * The API parameter a quality search carries until it is resolved: the check as written in the URL
 * (quality=<rule>[:<stat code>]). resolveSearchResource (search-requests.ts) turns it into the
 * PostgREST path and parameters by qualitySearchResource; it is never sent to PostgREST.
 */
export const QUALITY_CHECK_PARAM = "quality_check";

/**
 * Below this many units at the time frame a check's list is read from the findings first; from it
 * on, statistical_unit is walked in the page's order. Owner decision 2026-11-26 (05pe0x), measured
 * on the Norway copy for a first page sorted by name: from the findings about 0.16 ms per listed
 * unit (2 units 9 ms, 17 units 36 ms, 11,009 units 1.75 s); walking the units 117 s for 2 units but
 * 0.08 s for 11,009 and 0.1 s for 161,571. Both paths use indexes that exist already
 * (quality_finding_count_idx, quality_finding_key, statistical_unit's sort indexes).
 */
export const QUALITY_FINDINGS_FIRST_BELOW = 1000;

/** Where a quality search reads its rows: a PostgREST path and its query parameters. */
export interface QualitySearchResource {
  readonly path: "statistical_unit" | "rpc/statistical_unit_quality";
  readonly params: URLSearchParams;
}

/**
 * The resource for a search that lists the units of one check. `params` are the search's own
 * parameters for statistical_unit (filters, existence at the time frame, order, paging); `units` is
 * the check's count at the time frame (the dashboard's count of quality_finding).
 *
 * Few units: rpc/statistical_unit_quality(quality_rule, valid_on, quality_stat_definition_id), which
 * starts from the check's findings at the instant; the instant replaces the existence filter, as
 * PostgREST applies computed-field filters only to a table. Many units: statistical_unit with the
 * check's findings as an inner embed, which walks the units in the page's order and stops at the
 * page. Both return the same rows (test/sql/411).
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
    next.set("quality_rule", check.rule);
    next.set("valid_on", validOn);
    if (check.statDefinitionId !== null) {
      next.set("quality_stat_definition_id", String(check.statDefinitionId));
    }
    return { path: "rpc/statistical_unit_quality", params: next };
  }
  next.set("select", "*,quality_finding!inner()");
  next.set("quality_finding.rule", `eq.${check.rule}`);
  next.set(
    "quality_finding.stat_definition_id",
    check.statDefinitionId === null ? "is.null" : `eq.${check.statDefinitionId}`
  );
  return { path: "statistical_unit", params: next };
}
