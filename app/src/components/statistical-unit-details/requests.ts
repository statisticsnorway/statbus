import {createClient} from "@/lib/supabase/server";

export async function getEnterpriseById(id: string) {
  const {data: enterprises, error} = await createClient()
    .from("enterprise")
    .select("*")
    .eq("id", id)
    .limit(1)

  return {enterprise: enterprises?.[0], error};
}

export async function getEstablishmentById(id: string) {
  const {data: establishments, error} = await createClient()
    .from("establishment")
    .select("*")
    .eq("id", id)
    .limit(1)

  return {establishment: establishments?.[0], error};
}

export async function getLegalUnitById(id: string) {
  const {data: legalUnits, error} = await createClient()
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .limit(1)

  return {legalUnit: legalUnits?.[0], error};
}

export async function getStatisticalUnitHierarchy(unitId: number, unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment") {
  const {data: hierarchy, error} = await createClient()
    .rpc('statistical_unit_hierarchy', {
      unit_id: unitId,
      unit_type: unitType
    }).returns<StatisticalUnitHierarchy>()

  return {hierarchy, error}
}
