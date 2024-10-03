import { createClient } from "@/utils/supabase/server";

export async function getEnterpriseById(id: string) {
  const client = createClient()
  const { data: enterprises, error } = await client
    .from("enterprise")
    .select("*")
    .eq("id", id)
    .limit(1);

  return { enterprise: enterprises?.[0], error };
}

export async function getEstablishmentById(id: string) {
  const client = createClient();
  const { data: establishments, error } = await client
    .from("establishment")
    .select("*")
    .eq("id", id)
    .limit(1);

  return { establishment: establishments?.[0], error };
}

export async function getLegalUnitById(id: string) {
  const client = createClient();
  const { data: legalUnits, error } = await client
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .limit(1);

  return { legalUnit: legalUnits?.[0], error };
}

export async function getStatisticalUnitHierarchy(
  unitId: number,
  unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment"
) {
  const client = createClient();
  const { data: hierarchy, error } = await client
    .rpc("statistical_unit_hierarchy", {
      unit_id: unitId,
      unit_type: unitType,
    })
    .returns<StatisticalUnitHierarchy>();

  return { hierarchy, error };
}
