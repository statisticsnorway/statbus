import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { PostgrestError } from "@supabase/supabase-js";

export async function getEnterpriseById(id: string) {
  const client = await createSupabaseSSRClient();
  const { data: enterprises, error } = await client
    .from("enterprise")
    .select("*")
    .eq("id", parseInt(id, 10))
    .limit(1);

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { enterprise: enterprises?.[0], error: errorWithName };
}

export async function getEstablishmentById(id: string) {
  const client = await createSupabaseSSRClient();
  const { data: establishments, error } = await client
    .from("establishment")
    .select("*")
    .eq("id", parseInt(id, 10))
    .limit(1);

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { establishment: establishments?.[0], error: errorWithName };
}

export async function getLegalUnitById(id: string) {
  const client = await createSupabaseSSRClient();
  const { data: legalUnits, error } = await client
    .from("legal_unit")
    .select("*")
    .eq("id", parseInt(id, 10))
    .limit(1);

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { legalUnit: legalUnits?.[0], error: errorWithName };
}

export async function getStatisticalUnitHierarchy(
  unitId: number,
  unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment"
): Promise<{ 
  hierarchy: StatisticalUnitHierarchy | null, 
  error: { name: string } & PostgrestError | null 
}> {
  const client = await createSupabaseSSRClient();
  try {
    const { data, error } = await client
      .rpc("statistical_unit_hierarchy", {
        unit_id: unitId,
        unit_type: unitType,
      })
      .single()
      .returns<StatisticalUnitHierarchy>();

    if (error) {
      return { 
        hierarchy: null, 
        error: { ...error, name: "supabase-error" } 
      };
    }
    
    // Validate that data has the expected structure
    if (data && 'enterprise' in data) {
      return { 
        hierarchy: data as StatisticalUnitHierarchy, 
        error: null 
      };
    } else {
      return { 
        hierarchy: null, 
        error: { 
          message: "Invalid hierarchy data structure", 
          name: "supabase-error",
          code: "PGRST116",
          details: "Missing enterprise property in hierarchy data",
          hint: ""
        } as { name: string } & PostgrestError
      };
    }
  } catch (error) {
    const postgrestError = error as PostgrestError;
    return { 
      hierarchy: null, 
      error: { ...postgrestError, name: "supabase-error" } 
    };
  }
}

export async function getStatisticalUnitDetails(
  unitId: number,
  unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment"
): Promise<{ 
  unit: StatisticalUnitDetails | null, 
  error: { name: string } & PostgrestError | null 
}> {
  const client = await createSupabaseSSRClient();
  try {
    const { data, error } = await client
      .rpc("statistical_unit_details", {
        unit_id: unitId,
        unit_type: unitType,
      })
      .single()
      .returns<StatisticalUnitDetails>();

    if (error) {
      return { 
        unit: null, 
        error: { ...error, name: "supabase-error" } 
      };
    }
    
    // Validate that data has the expected structure
    if (data && (
      'enterprise' in data || 
      'legal_unit' in data || 
      'establishment' in data
    )) {
      return { 
        unit: data as StatisticalUnitDetails, 
        error: null 
      };
    } else {
      return { 
        unit: null, 
        error: { 
          message: "Invalid unit details data structure", 
          name: "supabase-error",
          code: "PGRST116",
          details: "Missing expected properties in unit details data",
          hint: ""
        } as { name: string } & PostgrestError
      };
    }
  } catch (error) {
    const postgrestError = error as PostgrestError;
    return { 
      unit: null, 
      error: { ...postgrestError, name: "supabase-error" } 
    };
  }
}

export async function getStatisticalUnitStats(
  unitId: number,
  unitType: "enterprise" | "enterprise_group" | "legal_unit" | "establishment"
) {
  const client = await createSupabaseSSRClient();
  const { data: stats, error } = await client
    .rpc("statistical_unit_stats", {
      unit_id: unitId,
      unit_type: unitType,
    })
    .returns<StatisticalUnitStats[]>();

  const errorWithName = error ? { ...error, name: "supabase-error" } : null;
  return { stats, error: errorWithName };
}
