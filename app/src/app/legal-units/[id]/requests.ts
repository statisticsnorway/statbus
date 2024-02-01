import {createClient} from "@/lib/supabase/server";

export async function getLegalUnitById(id: string) {
  const {data: legalUnit} = await createClient()
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .single()

  return legalUnit;
}
