import {createClient} from "@/lib/supabase/server";

export async function getEnterpriseById(id: string) {
  const {data: enterprise} = await createClient()
    .from("enterprise")
    .select("*")
    .eq("id", id)
    .single()

  return enterprise;
}
