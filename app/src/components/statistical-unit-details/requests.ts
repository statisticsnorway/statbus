import { createSupabaseSSRClient } from "@/utils/supabase/server";

export async function getEnterpriseById(id: string) {
  const client = await createSupabaseSSRClient()
  const { data: enterprises, error } = await client
    .from("enterprise")
    .select("*")
    .eq("id", id)
    .limit(1);

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { enterprise: enterprises?.[0], error: errorWithName };
}

export async function getEstablishmentById(id: string) {
  const client = await createSupabaseSSRClient();
  const { data: establishments, error } = await client
    .from("establishment")
    .select("*")
    .eq("id", id)
    .limit(1);

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { establishment: establishments?.[0], error: errorWithName };
}

export async function getLegalUnitById(id: string) {
  const client = await createSupabaseSSRClient();
  const { data: legalUnits, error } = await client
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .limit(1);

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { legalUnit: legalUnits?.[0], error: errorWithName };
}

export async function getStatisticalUnitHierarchy(
  unitId: number,
  unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment"
) {
  const client = await createSupabaseSSRClient();
  const { data: hierarchy, error } = await client
    .rpc("statistical_unit_hierarchy", {
      unit_id: unitId,
      unit_type: unitType,
    })
    .returns<StatisticalUnitHierarchy>();

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { hierarchy, error: errorWithName };
}

export async function getStatisticalUnitDetails(
  unitId: number,
  unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment"
) {
  const client = await createSupabaseSSRClient();
  const { data: unit, error } = await client
    .rpc("statistical_unit_details", {
      unit_id: unitId,
      unit_type: unitType,
    })
    .returns<StatisticalUnitDetails>();

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { unit, error: errorWithName };
}
