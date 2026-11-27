"use client";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useTimeFrame } from "@/atoms/app-derived";
import { useBaseData } from "@/atoms/base-data";
import { useDataVersion } from "@/components/exact-count";
import { useSWRWithAuthRefresh, isJwtExpiredError, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";
import { whereExistsOn } from "@/lib/unit-existence";
import {
  qualityMarksByPlace,
  unitQualityFindings,
  type UnitQualityFinding,
} from "@/lib/quality-marks";

type MarkedUnitType = "legal_unit" | "establishment";

function failOn(error: { code?: string; message: string } | null, what: string) {
  if (!error) return;
  if (isJwtExpiredError(error)) throw new JwtExpiredError();
  throw new Error(`Reading ${what} failed: ${error.message}`);
}

/**
 * The ids of the checks a unit is listed under at validOn: its statistical_unit row's row checks
 * (quality_check_ids) and its rows in the relation tables, each by the row's existence dates, as the
 * dashboard counts them (public.quality_check_count). Relation checks list legal units only.
 */
async function readListedCheckIds(unitId: number, unitType: MarkedUnitType, validOn: string) {
  const client = await getBrowserRestClient();
  const rowChecks = whereExistsOn(
    client
      .from("statistical_unit")
      .select("quality_check_ids")
      .eq("unit_type", unitType)
      .eq("unit_id", unitId),
    validOn
  );
  const relationTables = ["quality_establishment_activity_differs", "quality_legal_unit_establishment_stat"] as const;
  const relationChecks = unitType === "legal_unit"
    ? relationTables.map((table) =>
        client
          .from(table)
          .select("check_id")
          .eq("unit_type", unitType)
          .eq("unit_id", unitId)
          .lte("existence_from", validOn)
          .gt("existence_until", validOn)
      )
    : [];
  const shown = client
    .from("quality_check")
    .select("id,rule,stat_definition_id")
    .eq("switched_on", true)
    // public.in_use(quality_check), a computed field PostgREST filters on (bxt67q).
    .filter("in_use", "is", true);

  const [rows, shownChecks, ...relations] = await Promise.all([rowChecks, shown, ...relationChecks]);
  failOn(rows.error, "the unit's row checks");
  failOn(shownChecks.error, "the quality checks");
  const ids = (rows.data ?? []).flatMap((r) => r.quality_check_ids ?? []);
  for (const relation of relations) {
    failOn(relation.error, "the unit's relation checks");
    ids.push(...(relation.data ?? []).map((r) => r.check_id));
  }
  return { ids, shownChecks: shownChecks.data ?? [] };
}

/**
 * The quality checks a unit's page marks at the selected time frame (b6f1pw), grouped by the field
 * they point at (qualityMarkKey): the checks the reports show (switched on and in use) that list
 * this unit. Read again when the data version changes, so a correction shows once its
 * recalculation is done.
 */
export function useUnitQualityMarks(id: string, unitType: MarkedUnitType) {
  const { selectedTimeFrame } = useTimeFrame();
  const validOn = selectedTimeFrame?.valid_on;
  const dataVersion = useDataVersion();
  const { statDefinitions } = useBaseData();

  const { data } = useSWRWithAuthRefresh(
    validOn ? ["quality-marks", id, unitType, validOn, dataVersion ?? ""] : null,
    ([, id, unitType, validOn]: [string, string, MarkedUnitType, string, string]) =>
      readListedCheckIds(parseInt(id, 10), unitType, validOn),
    { revalidateOnFocus: false },
    "useUnitQualityMarks"
  );

  if (!data) return new Map<string, readonly UnitQualityFinding[]>();
  const statNameById = new Map(
    statDefinitions.map((s) => [s.id!, s.name ?? s.code ?? ""] as const)
  );
  return qualityMarksByPlace(unitQualityFindings(data.ids, data.shownChecks, statNameById));
}
