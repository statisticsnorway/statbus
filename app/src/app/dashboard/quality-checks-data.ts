"use client";

import { useState } from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useDataVersion } from "@/components/exact-count";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import type { QualityRule } from "@/lib/quality-checks";

/** A check of public.quality_check, with its variable's code and name for a per-variable rule. */
export interface QualityCheckRow {
  readonly rule: QualityRule;
  readonly statDefinitionId: number | null;
  readonly statCode: string | null;
  readonly statName: string | null;
  readonly onDashboard: boolean;
  readonly priority: number;
}

/** The key of a check among the counts: the rule and its variable id, 0 for none. */
export function qualityCheckKey(rule: QualityRule, statDefinitionId: number | null): string {
  return `${rule}:${statDefinitionId ?? 0}`;
}

/**
 * Every check of the installation (public.quality_check), in its order, with the variable's code
 * and name; null until read. Read again when the data version changes (a variable added, enabled
 * or disabled changes the checks, and ends in a recalculation) and when `version` changes (a
 * switch written on the admin page).
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
          client.from("quality_check").select("rule,stat_definition_id,on_dashboard,priority").order("priority"),
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
          checks: (checks.data ?? []).flatMap((c) =>
            c.rule === null
              ? []
              : [
                  {
                    rule: c.rule,
                    statDefinitionId: c.stat_definition_id,
                    statCode: c.stat_definition_id === null ? null : statById.get(c.stat_definition_id)?.code ?? null,
                    statName: c.stat_definition_id === null ? null : statById.get(c.stat_definition_id)?.name ?? null,
                    onDashboard: c.on_dashboard ?? false,
                    priority: c.priority ?? 0,
                  },
                ]
          ),
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
 * The number of units each check lists at validOn, from one grouped request on
 * public.quality_finding (its existence dates are the statistical_unit row's), keyed by
 * qualityCheckKey. A check with no findings is absent from the map: it lists 0 units. Counted
 * once per date and data version (useDataVersion), so a recalculation refreshes every card.
 */
export function useQualityFindingCounts(validOn: string | null): {
  counts: Map<string, number> | null;
  failed: boolean;
} {
  const dataVersion = useDataVersion();
  const [state, setState] = useState<{ key: string | null; counts: Map<string, number> | null; failed: boolean }>({
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
        const { data, error } = await client
          .from("quality_finding")
          .select("rule,stat_definition_id,count()")
          .lte("existence_from", validOn)
          .gt("existence_until", validOn);
        if (cancelled) return;
        if (error || !data) {
          console.error("Counting the quality findings failed:", error);
          setState({ key, counts: null, failed: true });
          return;
        }
        const rows = data as unknown as GroupedCount[];
        setState({
          key,
          failed: false,
          counts: new Map(rows.map((r) => [qualityCheckKey(r.rule, r.stat_definition_id), r.count])),
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

/** One row of the grouped count: PostgREST's count() grouped by the other selected columns. */
interface GroupedCount {
  rule: QualityRule;
  stat_definition_id: number | null;
  count: number;
}
