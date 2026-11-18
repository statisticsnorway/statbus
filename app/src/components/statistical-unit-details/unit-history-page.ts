import { PostgrestClient, PostgrestError } from "@supabase/postgrest-js";
import { Database } from "@/lib/database.types";
import type { UnitHistory } from "./unit-history-table";

/**
 * How many of a unit's versions the history table shows at a time. A unit
 * gains a version on every change to it or its records (a monthly import adds
 * about 12 a year), so the page never reads the whole history at once
 * (owner 2026-11-16, cgtb4y).
 */
export const HISTORY_PAGE_SIZE = 50;

export type HistoryUnitType = "legal_unit" | "establishment" | "enterprise";

export interface UnitHistoryPage {
  /** Up to HISTORY_PAGE_SIZE versions, newest first. */
  versions: UnitHistory[];
  /** The version just older than the page, which its last row compares with; null after the oldest. */
  nextOlder: UnitHistory | null;
  /** How many versions the unit has in all. */
  total: number;
  error: PostgrestError | null;
}

const HISTORY_SELECT = `*,
  physical_region(code,name),primary_activity_category(code,name),secondary_activity_category(code,name),status(code,name),sector(code,name),legal_form(code,name)`;

/**
 * One page of a unit's history from statistical_unit, newest first, starting
 * after `offset` newer versions. It reads one version more than the page, so
 * the page's last row can show what changed from the version below it.
 */
export async function fetchUnitHistoryPage(
  client: PostgrestClient<Database>,
  unitId: number,
  unitType: HistoryUnitType,
  offset: number
): Promise<UnitHistoryPage> {
  const { data, count, error } = await client
    .from("statistical_unit")
    .select(HISTORY_SELECT, { count: "exact" })
    .eq("unit_id", unitId)
    .eq("unit_type", unitType)
    .order("valid_from", { ascending: false })
    .range(offset, offset + HISTORY_PAGE_SIZE)
    .returns<UnitHistory[]>();
  const rows = data ?? [];
  return {
    versions: rows.slice(0, HISTORY_PAGE_SIZE),
    nextOlder: rows[HISTORY_PAGE_SIZE] ?? null,
    total: count ?? 0,
    error,
  };
}
