import {createClient} from "@/lib/supabase/server";

export async function getLegalUnitById(id: string) {
  const {data: legalUnits, error} = await createClient()
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .limit(1)

  return {legalUnit: legalUnits?.[0], error};
}
