"use client";

import { useState } from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useDataVersion } from "@/components/exact-count";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import type { QualityRule } from "@/lib/quality-checks";

/** A check of public.quality_check in use (public.in_use), with its variable's code and name. */
export interface QualityCheckRow {
  /** public.quality_check.id, the key of its count (useQualityFindingCounts). */
  readonly id: number;
  readonly rule: QualityRule;
  readonly statDefinitionId: number | null;
  readonly statCode: string | null;
  readonly statName: string | null;
  readonly onDashboard: boolean;
  readonly priority: number;
}

/**
 * Every check of the installation in use (public.quality_check, public.in_use: bxt67q), in its
 * order, with the variable's code and name; null until read. Read again when the data version
 * changes (a variable added, enabled or disabled changes the checks in use, and ends in a
 * recalculation) and when `version` changes (a switch written on the admin page).
 */
export function useQualityChecks(version = 0): {
  checks: QualityCheckRow[] | null;
  error: boolean;
} {
  const dataVersion = useDataVersion();
  const [state, setState] = useState<{ checks: QualityCheckRow[] | null; error: boolean }>({
    checks: null,
    error: false,
  });
  useGuardedEffect(
    () => {
      let cancelled = false;
      (async () => {
        const client = await getBrowserRestClient();
        const [checks, stats] = await Promise.all([
          client
            .from("quality_check")
            .select("id,rule,stat_definition_id,switched_on,priority")
            // public.in_use(quality_check), a computed field PostgREST filters on (bxt67q).
            .filter("in_use", "is", true)
            .order("priority"),
          client.from("stat_definition").select("id,code,name"),
        ]);
        if (cancelled) return;
        if (checks.error || stats.error) {
          console.error("Reading the quality checks failed:", checks.error ?? stats.error);
          setState({ checks: null, error: true });
          return;
        }
        const statById = new Map((stats.data ?? []).map((s) => [s.id, s]));
        setState({
          error: false,
          checks: (checks.data ?? []).map((c) => ({
            id: c.id,
            rule: c.rule,
            statDefinitionId: c.stat_definition_id,
            statCode: c.stat_definition_id === null ? null : statById.get(c.stat_definition_id)?.code ?? null,
            statName: c.stat_definition_id === null ? null : statById.get(c.stat_definition_id)?.name ?? null,
            onDashboard: c.switched_on,
            priority: c.priority,
          })),
        });
      })();
      return () => {
        cancelled = true;
      };
    },
    [version, dataVersion],
    "useQualityChecks:read"
  );
  return state;
}

/**
 * The number of units each check in use lists at validOn, from one request
 * (rpc/quality_check_count: a grouped count over statistical_unit.quality_check_ids and the relation
 * tables, by the statistical_unit rows' existence dates), keyed by the check's id. Counted once per
 * date and data version (useDataVersion), so a recalculation refreshes every card.
 */
export function useQualityFindingCounts(validOn: string | null): {
  counts: Map<number, number> | null;
  failed: boolean;
} {
  const dataVersion = useDataVersion();
  const [state, setState] = useState<{ key: string | null; counts: Map<number, number> | null; failed: boolean }>({
    key: null,
    counts: null,
    failed: false,
  });
  const key = validOn && dataVersion ? `${validOn}@${dataVersion}` : null;

  useGuardedEffect(
    () => {
      if (!key || !validOn) return;
      let cancelled = false;
      (async () => {
        const client = await getBrowserRestClient();
        const { data, error } = await client.rpc("quality_check_count", { valid_on: validOn });
        if (cancelled) return;
        if (error || !data) {
          console.error("Counting the quality findings failed:", error);
          setState({ key, counts: null, failed: true });
          return;
        }
        const rows = data as unknown as QualityCheckCount[];
        setState({
          key,
          failed: false,
          counts: new Map(rows.map((r) => [r.check_id, r.units])),
        });
      })();
      return () => {
        cancelled = true;
      };
    },
    [key, validOn],
    "useQualityFindingCounts:count"
  );

  return state.key === key ? { counts: state.counts, failed: state.failed } : { counts: null, failed: false };
}

/**
 * One row of rpc/quality_check_count (RETURNS TABLE, which the generated types leave untyped): a
 * check in use and the units it lists at the instant.
 */
export interface QualityCheckCount {
  check_id: number;
  units: number;
}
